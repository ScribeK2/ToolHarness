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
end
