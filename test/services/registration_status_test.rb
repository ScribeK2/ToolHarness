require "test_helper"

class RegistrationStatusTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  RDAP_REGISTERED = {
    success: true, record_type: :domain, source: :rdap_registry,
    query: "example.com", registrar: "MarkMonitor Inc.", expiration_date: "2027-08-13",
    creation_date: nil, updated_date: nil, nameservers: %w[a.iana-servers.net],
    registrant: nil, statuses: [], entities: [], raw_data: "{}", error: nil, issues: []
  }.freeze

  RDAP_NOT_FOUND = {
    success: true, record_type: :domain, source: :rdap_registry,
    query: "totally-unregistered-example.com", raw_data: nil, error: nil,
    issues: [{ severity: "info", code: "rdap_not_found", title: "Not registered",
               message: "RDAP reports no record.", recommendation: "The object may be unregistered or available." }]
  }.freeze

  RDAP_FAILED = { success: false, record_type: :domain, source: nil, query: "example.com", issues: [], error: "no endpoint" }.freeze

  test "registered when RDAP returns a registrar" do
    RdapChecker.stub(:check, RDAP_REGISTERED) do
      status = RegistrationStatus.check("example.com")
      assert status[:success]
      assert_equal true, status[:registered]
      assert_equal "MarkMonitor Inc.", status[:registrar]
    end
  end

  test "unregistered when RDAP reports rdap_not_found" do
    RdapChecker.stub(:check, RDAP_NOT_FOUND) do
      status = RegistrationStatus.check("totally-unregistered-example.com")
      assert status[:success]
      assert_equal false, status[:registered]
    end
  end

  test "registered when RDAP succeeds but returns a sparse response with no registrar/dates" do
    # A thin/sparse RDAP registry response is a real shape for a domain that
    # IS registered (no rdap_not_found issue is emitted) — the "looks empty"
    # heuristic must be scoped to WHOIS-sourced results only, or this would
    # be misclassified as unregistered.
    rdap_sparse = { success: true, record_type: :domain, source: :rdap_registry,
                    query: "example.com", registrar: nil, expiration_date: nil,
                    creation_date: nil, nameservers: [], raw_data: "{}", error: nil, issues: [] }
    RdapChecker.stub(:check, rdap_sparse) do
      status = RegistrationStatus.check("example.com")
      assert status[:success]
      assert_equal true, status[:registered]
    end
  end

  test "falls back to WHOIS when RDAP fails, registered when WHOIS has a registrar" do
    whois_ok = { success: true, record_type: :domain, source: :whois_fallback, registrar: "Reg",
                 expiration_date: "2030-01-01", creation_date: "2010-01-01", nameservers: [],
                 raw_data: "raw", issues: [], error: nil }
    RdapChecker.stub(:check, RDAP_FAILED) do
      WhoisChecker.stub(:check, whois_ok) do
        status = RegistrationStatus.check("example.com")
        assert status[:success]
        assert_equal true, status[:registered]
      end
    end
  end

  test "unregistered when WHOIS succeeds with no registrar/expiration/creation data" do
    whois_empty = { success: true, record_type: :domain, source: :whois_fallback, registrar: nil,
                    expiration_date: nil, creation_date: nil, nameservers: [], raw_data: "No match",
                    issues: [], error: nil }
    RdapChecker.stub(:check, RDAP_FAILED) do
      WhoisChecker.stub(:check, whois_empty) do
        status = RegistrationStatus.check("some-available-domain.com")
        assert status[:success]
        assert_equal false, status[:registered]
      end
    end
  end

  test "fails outright when both RDAP and WHOIS fail" do
    whois_fail = { success: false, record_type: :domain, source: :whois_fallback, error: "timeout", issues: [] }
    RdapChecker.stub(:check, RDAP_FAILED) do
      WhoisChecker.stub(:check, whois_fail) do
        status = RegistrationStatus.check("example.com")
        refute status[:success]
      end
    end
  end
end
