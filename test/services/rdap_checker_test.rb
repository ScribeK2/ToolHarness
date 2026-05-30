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
end
