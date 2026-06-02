require "test_helper"

class Rdap::WhoisFormatterTest < ActiveSupport::TestCase
  def domain_response
    {
      "objectClassName" => "domain",
      "ldhName" => "example.com",
      "handle" => "2336799_DOMAIN_COM-VRSN",
      "status" => ["client transfer prohibited", "active"],
      "events" => [
        { "eventAction" => "registration", "eventDate" => "1995-08-14T04:00:00Z" },
        { "eventAction" => "expiration",   "eventDate" => "2026-08-13T04:00:00Z" },
        { "eventAction" => "last changed", "eventDate" => "2024-01-02T00:00:00Z" }
      ],
      "nameservers" => [
        { "ldhName" => "A.IANA-SERVERS.NET" },
        { "ldhName" => "B.IANA-SERVERS.NET" }
      ],
      "secureDNS" => { "delegationSigned" => false },
      "entities" => [
        {
          "roles" => ["registrar"],
          "vcardArray" => ["vcard", [["fn", {}, "text", "Example Registrar, Inc."]]],
          "publicIds" => [{ "type" => "IANA Registrar ID", "identifier" => "292" }],
          "links" => [{ "rel" => "about", "href" => "https://example-registrar.example" }],
          "entities" => [
            {
              "roles" => ["abuse"],
              "vcardArray" => ["vcard", [
                ["email", {}, "text", "abuse@example-registrar.example"],
                ["tel", {}, "uri", "tel:+1.5555551234"]
              ]]
            }
          ]
        },
        {
          "roles" => ["registrant"],
          "vcardArray" => ["vcard", [["org", {}, "text", "Example Holdings LLC"]]]
        }
      ]
    }
  end

  test "domain output is whois-style with the standard field set" do
    out = Rdap::WhoisFormatter.format(domain_response, record_type: :domain)
    assert_match(/^Domain Name: example\.com$/, out)
    assert_match(/^Registry Domain ID: 2336799_DOMAIN_COM-VRSN$/, out)
    assert_match(/^Registrar: Example Registrar, Inc\.$/, out)
    assert_match(/^Registrar IANA ID: 292$/, out)
    assert_match(%r{^Registrar URL: https://example-registrar\.example$}, out)
    assert_match(/^Creation Date: 1995-08-14T/, out)
    assert_match(/^Registry Expiry Date: 2026-08-13T/, out)
    assert_match(/^Updated Date: 2024-01-02T/, out)
    assert_match(/^DNSSEC: unsigned$/, out)
    assert_match(/^Registrant Organization: Example Holdings LLC$/, out)
    assert_match(/^Abuse Contact Email: abuse@example-registrar\.example$/, out)
  end

  test "domain status maps RDAP strings to EPP camelCase, one line each" do
    out = Rdap::WhoisFormatter.format(domain_response, record_type: :domain)
    assert_match(/^Domain Status: clientTransferProhibited$/, out)
    assert_match(/^Domain Status: ok$/, out) # RDAP "active" -> EPP "ok"
  end

  test "nameservers are one line each, lowercased" do
    out = Rdap::WhoisFormatter.format(domain_response, record_type: :domain)
    assert_match(/^Name Server: a\.iana-servers\.net$/, out)
    assert_match(/^Name Server: b\.iana-servers\.net$/, out)
  end

  test "absent fields are omitted, not blank" do
    out = Rdap::WhoisFormatter.format({ "ldhName" => "bare.com" }, record_type: :domain)
    assert_equal "Domain Name: bare.com", out
    refute_match(/Registrar:/, out)
  end
end
