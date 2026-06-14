require "test_helper"

class Tools::EmailHeaderAnalyzerTest < ActiveSupport::TestCase
  def fixture(name)
    Rails.root.join("test/fixtures/files/email_headers/#{name}").read
  end

  # Stub every network boundary origin enrichment touches, so tests stay offline.
  def with_stubs(rdap: { success: true }, listings: [],
                 ipinfo_token: nil, ipinfo: { success: true }, &blk)
    store = Object.new
    store.define_singleton_method(:secret_for) { |_id| ipinfo_token }
    ToolHarness::CredentialStore.stub(:new, store) do
      RdapChecker.stub(:check, rdap) do
        IpinfoChecker.stub(:check, ipinfo) do
          Tools::Blacklist.stub(:new, fake_blacklist(listings), &blk)
        end
      end
    end
  end

  def fake_blacklist(listings)
    fake = Object.new
    res = ToolHarness::Result.new(success: true, tool: "bl", data: { listings: listings })
    fake.define_singleton_method(:execute) { |_params| res }
    fake
  end

  test "empty paste -> unsuccessful Result, no raise" do
    res = Tools::EmailHeaderAnalyzer.new.execute(headers: "   ")
    assert_not res.success
    assert_match(/no email headers/i, res.summary.to_s + res.error.to_s)
  end

  test "spoofed fixture -> critical spoofing issue and dmarc-fail issue, origin ip present" do
    with_stubs do
      res = Tools::EmailHeaderAnalyzer.new.execute(headers: fixture("spoofed.txt"))
      assert res.success
      titles = res.issues.map { |i| i["title"] }
      assert(titles.any? { |t| t =~ /dmarc/i }, "expected a dmarc issue, got: #{titles.inspect}")
      assert(titles.any? { |t| t =~ /spoof|alignment/i }, "expected spoofing/alignment, got: #{titles.inspect}")
      assert_equal "198.51.100.66", res.data[:origin][:ip]
    end
  end

  test "gmail fixture -> no critical issues, summary mentions pass" do
    with_stubs do
      res = Tools::EmailHeaderAnalyzer.new.execute(headers: fixture("gmail.txt"))
      assert res.success
      assert_empty res.critical_issues
      assert_match(/pass/i, res.summary)
    end
  end

  test "enriches origin IP: RDAP name, blacklist listings, IPinfo when key present" do
    rdap = { success: true, network_name: "EXAMPLE-NET", organization: "Example Org",
             raw_data: '{"name":"EXAMPLE-NET"}' }   # raw_data is a JSON STRING, like the real checker
    ipi  = { success: true, asn: { id: "AS64500", name: "Example ISP" }, org: "Example ISP",
             city: "Reno", country: "US", privacy: { hosting: true } }
    with_stubs(rdap: rdap, listings: [{ name: "Spamhaus ZEN" }], ipinfo_token: "tok", ipinfo: ipi) do
      res = Tools::EmailHeaderAnalyzer.new.execute(headers: fixture("spoofed.txt"))
      o = res.data[:origin]
      assert_equal "198.51.100.66", o[:ip]
      assert_equal "EXAMPLE-NET", o[:rdap_name]
      assert_equal ["Spamhaus ZEN"], o[:blacklist_listings]
      assert_equal "Example ISP", o[:ipinfo][:org]
      assert(res.issues.any? { |i| i["title"] =~ /blacklist/i })
    end
  end

  test "no IPinfo key -> ipinfo block nil, other enrichment still runs" do
    rdap = { success: true, network_name: "EXAMPLE-NET", raw_data: '{"name":"EXAMPLE-NET"}' }
    with_stubs(rdap: rdap, listings: [], ipinfo_token: nil) do
      res = Tools::EmailHeaderAnalyzer.new.execute(headers: fixture("spoofed.txt"))
      assert_nil res.data[:origin][:ipinfo]
      assert_equal "EXAMPLE-NET", res.data[:origin][:rdap_name]
    end
  end

  test "no originating IP (minimal fixture) -> origin.ip nil, enrichment skipped" do
    res = Tools::EmailHeaderAnalyzer.new.execute(headers: fixture("minimal.txt"))
    assert_nil res.data[:origin][:ip]
  end

  test "minimal headers (no Return-Path/Message-ID) -> no misalignment issue" do
    res = Tools::EmailHeaderAnalyzer.new.execute(headers: fixture("minimal.txt"))
    assert res.success
    titles = res.issues.map { |i| i["title"] }
    assert(titles.none? { |t| t =~ /align/i }, "should not flag alignment when there is nothing to compare, got: #{titles.inspect}")
  end
end
