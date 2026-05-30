require "test_helper"

class Tools::WhoisLookupTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  RDAP_OK = {
    success: true, record_type: :domain, source: :rdap_registry,
    query: "example.com", registrar: "MarkMonitor Inc.", expiration_date: "2027-08-13",
    creation_date: nil, updated_date: nil, nameservers: %w[a.iana-servers.net],
    registrant: nil, statuses: [], entities: [], raw_data: "{}", error: nil, issues: []
  }.freeze

  test "uses RDAP when it succeeds and does not call WHOIS" do
    RdapChecker.stub(:check, RDAP_OK) do
      WhoisChecker.stub(:check, ->(*) { flunk "WHOIS should not be called" }) do
        result = Tools::WhoisLookup.new.execute(domain: "example.com")
        assert result.success
        assert_equal :rdap_registry, result.data[:source]
        assert_equal "MarkMonitor Inc.", result.data[:registrar]
      end
    end
  end

  test "falls back to WHOIS when RDAP fails (domain)" do
    rdap_fail = { success: false, record_type: :domain, source: nil, query: "example.com", issues: [], error: "x" }
    whois_ok = { success: true, record_type: :domain, source: :whois_fallback, registrar: "Reg",
                 expiration_date: nil, nameservers: [], raw_data: "raw", issues: [], error: nil }
    RdapChecker.stub(:check, rdap_fail) do
      WhoisChecker.stub(:check, whois_ok) do
        result = Tools::WhoisLookup.new.execute(domain: "example.com")
        assert result.success
        assert_equal :whois_fallback, result.data[:source]
      end
    end
  end

  test "result_partial points at the custom view" do
    assert_equal "results/tools/whois_lookup", Tools::WhoisLookup.result_partial
  end
end
