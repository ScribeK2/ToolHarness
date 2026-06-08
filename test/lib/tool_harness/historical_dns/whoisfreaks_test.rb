require "test_helper"

class ToolHarness::HistoricalDns::WhoisfreaksTest < ActiveSupport::TestCase
  def provider = ToolHarness::HistoricalDns::Whoisfreaks.new

  # Real response shape (verified live 2026-06-08): historicalDnsRecords is an array of
  # snapshots, each with a queryTime (the observation date) and a nested dnsRecords array
  # whose records carry rawText (full BIND line) + singleName. No per-record timestamps.
  def self.snap(query_time, raw_lines, dns_type)
    {
      "queryTime" => query_time,
      "dnsRecords" => raw_lines.map { |rt| { "dnsType" => dns_type, "rawText" => rt, "singleName" => rt.split(/\s+/).last } }
    }
  end

  BODIES = {
    "a"    => { "totalPages" => 1, "historicalDnsRecords" => [
                 snap("2021-02-01", ["example.com.\t300\tIN\tA\t1.2.3.4"], "A")
               ] },
    "aaaa" => { "totalPages" => 1, "historicalDnsRecords" => [] },
    "ns"   => { "totalPages" => 1, "historicalDnsRecords" => [
                 snap("2021-02-01", ["example.com.\t3600\tIN\tNS\tNS1.OurHost.com."], "NS"),
                 snap("2024-03-01", ["example.com.\t3600\tIN\tNS\tdana.ns.cloudflare.com."], "NS")
               ] },
    "mx"   => { "totalPages" => 1, "historicalDnsRecords" => [
                 snap("2021-02-01", ["example.com.\t3600\tIN\tMX\t10 mail.example.com."], "MX")
               ] },
    "txt"  => { "totalPages" => 1, "historicalDnsRecords" => [
                 snap("2022-01-01", ["example.com.\t3600\tIN\tTXT\t\"v=spf1 include:_spf.google.com ~all\""], "TXT")
               ] }
  }.freeze

  def stub_fetch(p, bodies = BODIES, status: 200)
    p.stub(:http_get_json, lambda { |url, *|
      type = url[/type=([a-z]+)/, 1]
      { status: status, body: bodies.fetch(type, { "totalPages" => 1, "historicalDnsRecords" => [] }) }
    }) { yield }
  end

  test "parses BIND rawText per type, normalizes values, and dates records by snapshot queryTime" do
    p = provider
    out = stub_fetch(p) { p.fetch("Example.com", key: "k") }
    recs = out[:records]
    assert_empty out[:subdomains]

    ns = recs.select { |r| r.type == :ns }
    assert_equal ["dana.ns.cloudflare.com", "ns1.ourhost.com"], ns.map(&:value).sort   # host-normalized
    old_ns = ns.find { |r| r.value == "ns1.ourhost.com" }
    assert_equal Date.new(2021, 2, 1), old_ns.first_seen                                # dated by queryTime
    assert_equal ["whoisfreaks"], old_ns.sources

    a = recs.find { |r| r.type == :a }
    assert_equal "1.2.3.4", a.value
    assert_equal Date.new(2021, 2, 1), a.first_seen

    mx = recs.find { |r| r.type == :mx }
    assert_equal "10 mail.example.com", mx.value

    txt = recs.find { |r| r.type == :txt }
    assert_equal "v=spf1 include:_spf.google.com ~all", txt.value

    assert_equal %i[a ns mx txt].sort, recs.map(&:type).uniq.sort
  end

  test "401 raises ProviderError(:bad_key)" do
    p = provider
    err = stub_fetch(p, status: 401) { assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com", key: "k") } }
    assert_equal :bad_key, err.category
  end

  test "credit-exhaustion body raises ProviderError(:no_credits)" do
    p = provider
    body = { "error" => "Insufficient credits to process this request" }
    err = p.stub(:http_get_json, ->(_url, *) { { status: 400, body: body } }) do
      assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com", key: "k") }
    end
    assert_equal :no_credits, err.category
  end

  test "total rate-limit (429 on first call) raises ProviderError(:rate_limited)" do
    p = provider
    body = { "status" => 429, "error" => "Too Many Requests", "message" => "Please slow down." }
    err = p.stub(:http_get_json, ->(_url, *) { { status: 429, body: body } }) do
      assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com", key: "k") }
    end
    assert_equal :rate_limited, err.category
  end

  test "partial rate-limit: first type succeeds, later type 429s -> returns partial, no raise" do
    p = provider
    # NS (fetched first) succeeds; everything else rate-limits.
    p.stub(:http_get_json, lambda { |url, *|
      if url.include?("type=ns")
        { status: 200, body: BODIES["ns"] }
      else
        { status: 429, body: { "message" => "Please slow down." } }
      end
    }) do
      out = p.fetch("example.com", key: "k")
      assert_equal %i[ns], out[:records].map(&:type).uniq    # only the pre-429 type came back
      assert out[:records].any?, "should return the NS records gathered before the 429"
    end
  end
end
