require "test_helper"

class WhoisCheckerTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  # Fake WHOIS record/client so tests never touch the network. The real code
  # does `Whois::Client.new(timeout:).lookup(@domain)` and reads `.content`.
  FakeRecord = Struct.new(:content)
  FakeClient = Struct.new(:raw) do
    def lookup(_q) = FakeRecord.new(raw)
  end
  def stub_lookup(raw)
    Whois::Client.stub(:new, ->(*) { FakeClient.new(raw) }) { yield }
  end

  test "does not shell out to system whois" do
    # AppImage rule: tools must not depend on host binaries.
    # Source-inspection enforces "no shell-outs in this file".
    src = File.read(Rails.root.join("app/services/whois_checker.rb"))
    refute_match(/\bsystem\s*\(/, src, "WhoisChecker must not call system()")
    refute_match(/`[^`]*whois[^`]*`/, src, "WhoisChecker must not backtick-shell to whois")
    refute_match(/Open3/, src, "WhoisChecker must not use Open3 to shell out")
  end

  test "IP lookup extracts network fields from ARIN-style whois" do
    raw = <<~WHOIS
      NetRange:       8.8.8.0 - 8.8.8.255
      CIDR:           8.8.8.0/24
      NetName:        GOGL
      Organization:   Google LLC (GOGL)
      Country:        US
      OrgAbuseEmail:  network-abuse@google.com
    WHOIS
    stub_lookup(raw) do
      result = WhoisChecker.check("8.8.8.8")
      assert result[:success]
      assert_equal :ip, result[:record_type]
      assert_equal "8.8.8.0/24", result[:cidr]
      assert_equal "GOGL", result[:network_name]
      assert_match "Google LLC", result[:organization].to_s
      assert_equal "network-abuse@google.com", result[:abuse_contact]
    end
  end

  test "domain lookup still reports record_type domain" do
    raw = "Domain Name: EXAMPLE.COM\nRegistrar: MarkMonitor Inc.\n"
    stub_lookup(raw) do
      result = WhoisChecker.check("example.com")
      assert_equal :domain, result[:record_type]
    end
  end

  test "detect_domain_issues is callable on a plain hash (for RDAP reuse)" do
    issues = WhoisChecker.detect_domain_issues(
      expiration_date: "2020-01-01", nameservers: %w[a.example.net], registrar: "X"
    )
    assert(issues.any? { |i| i[:code] == "domain_expired" })
  end
end
