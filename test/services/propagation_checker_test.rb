require "test_helper"

class PropagationCheckerTest < ActiveSupport::TestCase
  # Lightweight RR stand-in for normalization tests. We only need
  # the attributes our normalizer reads.
  RR = Struct.new(:type, :address, :preference, :exchange, :nsdname, :rdata,
                  :strings, :mname, :rname, :serial, :flags, :tag, :value, :ttl)

  def normalize(type, rrs)
    PropagationChecker.new("ex.com", record_type: type)
      .send(:normalize_values, type, rrs)
  end

  test "normalize A: addresses as strings, sorted" do
    rrs = [
      RR.new(Dnsruby::Types::A, "1.2.3.4", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 3600),
      RR.new(Dnsruby::Types::A, "9.9.9.9", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 3600)
    ]
    assert_equal ["1.2.3.4", "9.9.9.9"], normalize("A", rrs)
  end

  test "normalize MX: priority-host strings, sorted by priority then host" do
    rrs = [
      RR.new(Dnsruby::Types::MX, nil, 20, "mx2.example.com.", nil, nil, nil, nil, nil, nil, nil, nil, nil, 3600),
      RR.new(Dnsruby::Types::MX, nil, 10, "mx1.example.com.", nil, nil, nil, nil, nil, nil, nil, nil, nil, 3600)
    ]
    assert_equal ["10 mx1.example.com", "20 mx2.example.com"], normalize("MX", rrs)
  end

  test "normalize NS: hostnames lowercased, trailing dot stripped, sorted" do
    rrs = [
      RR.new(Dnsruby::Types::NS, nil, nil, nil, "B.NS.example.com.", nil, nil, nil, nil, nil, nil, nil, nil, 3600),
      RR.new(Dnsruby::Types::NS, nil, nil, nil, "a.ns.example.com.", nil, nil, nil, nil, nil, nil, nil, nil, 3600)
    ]
    assert_equal ["a.ns.example.com", "b.ns.example.com"], normalize("NS", rrs)
  end

  test "normalize CNAME: rdata lowercased, trailing dot stripped" do
    rrs = [ RR.new(Dnsruby::Types::CNAME, nil, nil, nil, nil, "target.example.com.", nil, nil, nil, nil, nil, nil, nil, 3600) ]
    assert_equal ["target.example.com"], normalize("CNAME", rrs)
  end

  test "normalize TXT: joined strings, sorted" do
    rrs = [
      RR.new(Dnsruby::Types::TXT, nil, nil, nil, nil, nil, ["v=spf1 ", "-all"], nil, nil, nil, nil, nil, nil, 3600),
      RR.new(Dnsruby::Types::TXT, nil, nil, nil, nil, nil, ["hello"], nil, nil, nil, nil, nil, nil, 3600)
    ]
    assert_equal ["hello", "v=spf1 -all"], normalize("TXT", rrs)
  end

  test "normalize SOA: mname rname serial" do
    rrs = [ RR.new(Dnsruby::Types::SOA, nil, nil, nil, nil, nil, nil, "ns1.example.com.", "hostmaster.example.com.", 2026052801, nil, nil, nil, 3600) ]
    assert_equal ["ns1.example.com hostmaster.example.com 2026052801"], normalize("SOA", rrs)
  end

  test "normalize CAA: flags tag value, sorted" do
    rrs = [
      RR.new(Dnsruby::Types::CAA, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0, "iodef", "mailto:abuse@example.com", 3600),
      RR.new(Dnsruby::Types::CAA, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0, "issue", "letsencrypt.org", 3600)
    ]
    assert_equal ["0 iodef mailto:abuse@example.com", "0 issue letsencrypt.org"], normalize("CAA", rrs)
  end

  test "RESOLVERS has 20 entries, each with id/ip/operator/region" do
    list = PropagationChecker::RESOLVERS
    assert_equal 20, list.size
    list.each do |r|
      assert r[:id].is_a?(String) && !r[:id].empty?, "missing id: #{r.inspect}"
      assert r[:ip] =~ /\A\d{1,3}(\.\d{1,3}){3}\z/, "bad ip: #{r.inspect}"
      assert r[:operator].is_a?(String) && !r[:operator].empty?
      assert r[:region].is_a?(String) && !r[:region].empty?
    end
  end

  test "RESOLVERS ids are unique" do
    ids = PropagationChecker::RESOLVERS.map { |r| r[:id] }
    assert_equal ids.uniq.size, ids.size, "duplicate resolver ids: #{ids - ids.uniq}"
  end

  test "RESOLVERS is frozen" do
    assert PropagationChecker::RESOLVERS.frozen?
  end

  # Programmable resolver used in place of Dnsruby::Resolver.
  # behavior is one of:
  #   { :ok => [RR, RR, ...] }   — returns an answer
  #   { :raise => ExceptionClass } — raises (NXDomain / ServFail / Refused / ResolvTimeout / OtherResolvError)
  #   { :sleep => seconds, :ok => [...] } — sleeps before returning (drives timeout via outer join)
  FakeResponse = Struct.new(:answer)

  FakeResolver = Struct.new(:ip, :behavior) do
    def query(name, type)
      sleep(behavior[:sleep]) if behavior[:sleep]
      raise behavior[:raise], "fake #{behavior[:raise]}" if behavior[:raise]
      FakeResponse.new(behavior[:ok])
    end
  end

  def factory(map)
    # map: { "8.8.8.8" => { ok: [...] }, "1.1.1.1" => { raise: Dnsruby::NXDomain }, ... }
    ->(ip) { FakeResolver.new(ip, map.fetch(ip) { { raise: Dnsruby::OtherResolvError } }) }
  end

  def a_rr(addr, ttl: 3600)
    RR.new(Dnsruby::Types::A, addr, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ttl)
  end

  test "query_one: OK response captures values, ttl, latency_ms" do
    fac = factory("8.8.8.8" => { ok: [a_rr("1.2.3.4", ttl: 600)] })
    checker = PropagationChecker.new("example.com", record_type: "A", resolver_factory: fac)
    entry = PropagationChecker::RESOLVERS.find { |r| r[:ip] == "8.8.8.8" }
    result = checker.send(:query_one, entry)

    assert_equal :ok, result[:status]
    assert_equal ["1.2.3.4"], result[:values]
    assert_equal 600, result[:ttl]
    assert_kind_of Integer, result[:latency_ms]
    assert result[:latency_ms] >= 0
    assert_equal "8.8.8.8", result[:ip]
    assert_equal "Google", result[:operator]
  end

  test "query_one: NXDomain mapped to :nxdomain" do
    fac = factory("8.8.8.8" => { raise: Dnsruby::NXDomain })
    checker = PropagationChecker.new("missing.example", record_type: "A", resolver_factory: fac)
    entry = PropagationChecker::RESOLVERS.find { |r| r[:ip] == "8.8.8.8" }
    result = checker.send(:query_one, entry)

    assert_equal :nxdomain, result[:status]
    assert_equal [], result[:values]
    assert_nil result[:ttl]
    refute_nil result[:error]
  end

  test "query_one: ServFail mapped to :servfail" do
    fac = factory("8.8.8.8" => { raise: Dnsruby::ServFail })
    checker = PropagationChecker.new("example.com", record_type: "A", resolver_factory: fac)
    entry = PropagationChecker::RESOLVERS.find { |r| r[:ip] == "8.8.8.8" }
    assert_equal :servfail, checker.send(:query_one, entry)[:status]
  end

  test "query_one: Refused mapped to :refused" do
    fac = factory("8.8.8.8" => { raise: Dnsruby::Refused })
    checker = PropagationChecker.new("example.com", record_type: "A", resolver_factory: fac)
    entry = PropagationChecker::RESOLVERS.find { |r| r[:ip] == "8.8.8.8" }
    assert_equal :refused, checker.send(:query_one, entry)[:status]
  end

  test "query_one: ResolvTimeout mapped to :timeout" do
    fac = factory("8.8.8.8" => { raise: Dnsruby::ResolvTimeout })
    checker = PropagationChecker.new("example.com", record_type: "A", resolver_factory: fac)
    entry = PropagationChecker::RESOLVERS.find { |r| r[:ip] == "8.8.8.8" }
    assert_equal :timeout, checker.send(:query_one, entry)[:status]
  end

  test "query_one: other ResolvError mapped to :error" do
    fac = factory("8.8.8.8" => { raise: Dnsruby::OtherResolvError })
    checker = PropagationChecker.new("example.com", record_type: "A", resolver_factory: fac)
    entry = PropagationChecker::RESOLVERS.find { |r| r[:ip] == "8.8.8.8" }
    assert_equal :error, checker.send(:query_one, entry)[:status]
  end

  test "query_one: ttl is the minimum across multiple RRs" do
    fac = factory("8.8.8.8" => { ok: [a_rr("1.2.3.4", ttl: 900), a_rr("1.2.3.5", ttl: 300)] })
    checker = PropagationChecker.new("example.com", record_type: "A", resolver_factory: fac)
    entry = PropagationChecker::RESOLVERS.find { |r| r[:ip] == "8.8.8.8" }
    assert_equal 300, checker.send(:query_one, entry)[:ttl]
  end
end
