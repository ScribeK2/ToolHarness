require "test_helper"

class RdapCheckerTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  DOMAIN_RDAP = {
    "objectClassName" => "domain",
    "ldhName" => "EXAMPLE.COM",
    "status" => ["client transfer prohibited"],
    "events" => [
      { "eventAction" => "registration", "eventDate" => "1995-08-14T04:00:00Z" },
      { "eventAction" => "expiration",   "eventDate" => "2027-08-13T04:00:00Z" },
      { "eventAction" => "last changed", "eventDate" => "2024-08-14T07:01:44Z" }
    ],
    "nameservers" => [
      { "ldhName" => "A.IANA-SERVERS.NET" },
      { "ldhName" => "B.IANA-SERVERS.NET" }
    ],
    "entities" => [
      {
        "roles" => ["registrar"],
        "vcardArray" => ["vcard", [
          ["version", {}, "text", "4.0"],
          ["fn", {}, "text", "RESERVED-Internet Assigned Numbers Authority"]
        ]]
      }
    ]
  }.freeze

  test "domain lookup via registry parses dates, ns, registrar, status" do
    boot = Rdap::Bootstrap.new
    boot.stub(:base_for, "https://rdap.verisign.com/com/v1/") do
      c = RdapChecker.new("example.com", bootstrap: boot)
      c.stub(:http_get_json, ->(_url) { { status: 200, body: DOMAIN_RDAP } }) do
        r = c.check
        assert r[:success]
        assert_equal :domain, r[:record_type]
        assert_equal :rdap_registry, r[:source]
        assert_equal "2027-08-13", r[:expiration_date][0, 10]
        assert_equal "1995-08-14", r[:creation_date][0, 10]
        assert_equal %w[a.iana-servers.net b.iana-servers.net], r[:nameservers]
        assert_equal "RESERVED-Internet Assigned Numbers Authority", r[:registrar]
        assert_includes r[:statuses], "client transfer prohibited"
      end
    end
  end

  test "falls back to rdap.org when bootstrap has no base" do
    boot = Rdap::Bootstrap.new
    boot.stub(:base_for, nil) do
      c = RdapChecker.new("example.com", bootstrap: boot)
      seen = []
      fake = ->(url) { seen << url; { status: 200, body: DOMAIN_RDAP } }
      c.stub(:http_get_json, fake) do
        r = c.check
        assert r[:success]
        assert_equal :rdap_bootstrap_redirect, r[:source]
        assert_match %r{rdap\.org/domain/example\.com}, seen.first
      end
    end
  end

  test "registry 5xx falls back to rdap.org" do
    boot = Rdap::Bootstrap.new
    boot.stub(:base_for, "https://rdap.verisign.com/com/v1/") do
      c = RdapChecker.new("example.com", bootstrap: boot)
      fake = ->(url) { url.include?("rdap.org") ? { status: 200, body: DOMAIN_RDAP } : { status: 503, body: nil } }
      c.stub(:http_get_json, fake) do
        r = c.check
        assert r[:success]
        assert_equal :rdap_bootstrap_redirect, r[:source]
      end
    end
  end

  test "registry 404 is authoritative not-registered (no fallback)" do
    boot = Rdap::Bootstrap.new
    boot.stub(:base_for, "https://rdap.verisign.com/com/v1/") do
      c = RdapChecker.new("nope.com", bootstrap: boot)
      c.stub(:http_get_json, ->(_) { { status: 404, body: nil } }) do
        r = c.check
        assert r[:success]
        assert(r[:issues].any? { |i| i[:code] == "rdap_not_found" })
      end
    end
  end

  test "total failure returns success false for WHOIS fallback" do
    boot = Rdap::Bootstrap.new
    boot.stub(:base_for, nil) do
      c = RdapChecker.new("example.com", bootstrap: boot)
      c.stub(:http_get_json, ->(_) { { status: 0, body: nil } }) do
        r = c.check
        assert_not r[:success]
      end
    end
  end

  IP_RDAP = {
    "objectClassName" => "ip network",
    "handle" => "NET-8-8-8-0-1",
    "startAddress" => "8.8.8.0",
    "endAddress" => "8.8.8.255",
    "ipVersion" => "v4",
    "name" => "GOGL",
    "type" => "DIRECT ALLOCATION",
    "country" => "US",
    "port43" => "whois.arin.net",
    "events" => [{ "eventAction" => "registration", "eventDate" => "2014-03-14T00:00:00Z" }],
    "entities" => [
      { "roles" => ["registrant"],
        "vcardArray" => ["vcard", [["version", {}, "text", "4.0"], ["fn", {}, "text", "Google LLC"]]] },
      { "roles" => ["abuse"],
        "vcardArray" => ["vcard", [["version", {}, "text", "4.0"], ["email", {}, "text", "abuse@google.com"]]] }
    ]
  }.freeze

  test "IP lookup parses network, range, org, and abuse contact" do
    boot = Rdap::Bootstrap.new
    boot.stub(:base_for, "https://rdap.arin.net/registry/") do
      c = RdapChecker.new("8.8.8.8", bootstrap: boot)
      c.stub(:http_get_json, ->(_) { { status: 200, body: IP_RDAP } }) do
        r = c.check
        assert r[:success]
        assert_equal :ip, r[:record_type]
        assert_equal "8.8.8.0 – 8.8.8.255", r[:ip_range]
        assert_equal "GOGL", r[:network_name]
        assert_equal "DIRECT ALLOCATION", r[:network_type]
        assert_equal "US", r[:country]
        assert_equal "Google LLC", r[:organization]
        assert_equal "abuse@google.com", r[:abuse_contact]
      end
    end
  end

  test "IP CIDR is the smallest block covering a non-power-of-2 range" do
    # 8.8.8.0–8.8.8.4 is 5 addresses; the covering CIDR is /29 (8 addresses),
    # not the /30 (4) that a floor would wrongly produce. Must match the value
    # Rdap::WhoisFormatter emits in the whois Raw block.
    body = IP_RDAP.merge("startAddress" => "8.8.8.0", "endAddress" => "8.8.8.4")
    boot = Rdap::Bootstrap.new
    boot.stub(:base_for, "https://rdap.arin.net/registry/") do
      c = RdapChecker.new("8.8.8.0", bootstrap: boot)
      c.stub(:http_get_json, ->(_) { { status: 200, body: body } }) do
        r = c.check
        assert_equal "8.8.8.0/29", r[:cidr]
        assert_match(%r{^CIDR: 8\.8\.8\.0/29$}, r[:whois_text])
      end
    end
  end

  test "RDAP domain results get expiry issues" do
    expired = DOMAIN_RDAP.merge("events" => [{ "eventAction" => "expiration", "eventDate" => "2020-01-01T00:00:00Z" }])
    boot = Rdap::Bootstrap.new
    boot.stub(:base_for, "https://rdap.verisign.com/com/v1/") do
      c = RdapChecker.new("example.com", bootstrap: boot)
      c.stub(:http_get_json, ->(_) { { status: 200, body: expired } }) do
        r = c.check
        assert(r[:issues].any? { |i| i[:code] == "domain_expired" })
      end
    end
  end
end
