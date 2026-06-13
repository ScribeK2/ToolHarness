require "test_helper"

class Tools::EmailAuthCheckTest < ActiveSupport::TestCase
  test "static metadata" do
    assert_equal "Email Authentication", Tools::EmailAuthCheck.tool_name
    assert_equal :domain, Tools::EmailAuthCheck.input_type
    refute Tools::EmailAuthCheck.cacheable?
  end

  test "form_fields exposes domain and scope select with full first (the default)" do
    ff = Tools::EmailAuthCheck.form_fields
    assert_equal :text, ff[:domain]
    assert_equal :select, ff[:scope][:type]
    assert_equal %w[full spf dkim dmarc], ff[:scope][:options]
  end

  test "registered under :email_auth_check; standalone record tools are gone" do
    assert_equal Tools::EmailAuthCheck, ToolHarness::Registry.find_tool(:email_auth_check)
    assert_nil ToolHarness::Registry.find_tool(:spf_check)
    assert_nil ToolHarness::Registry.find_tool(:dkim_check)
    assert_nil ToolHarness::Registry.find_tool(:dmarc_check)
  end

  test "scope=spf runs only SpfChecker and skips the grade" do
    canned = { success: true, all_mechanism: { qualifier: "~" }, includes: [],
               dns_lookup_count: 3, issues: [] }
    SpfChecker.stub(:check, canned) do
      res = Tools::EmailAuthCheck.new.execute(domain: "example.com", scope: "spf")
      assert res.success
      assert_equal "spf", res.data[:scope]
      assert_nil res.data[:authentication_grade]
      assert_match(/SPF record found/, res.summary)
    end
  end

  test "scope=dkim summary reports selectors found" do
    canned = { success: true, selectors_checked: 12,
               selectors_found: [{ selector: "google" }], issues: [] }
    DkimChecker.stub(:check, canned) do
      res = Tools::EmailAuthCheck.new.execute(domain: "example.com", scope: "dkim")
      assert_match(/1 of 12 selectors found/, res.summary)
    end
  end

  test "scope=dmarc summary reports policy" do
    canned = { success: true, policy: "reject", percentage: 100, rua: ["a@b"], issues: [] }
    DmarcChecker.stub(:check, canned) do
      res = Tools::EmailAuthCheck.new.execute(domain: "example.com", scope: "dmarc")
      assert_match(/p=reject/, res.summary)
    end
  end

  test "blank or unknown scope falls back to the full overview" do
    full = { success: true, authentication_grade: "B", authentication_score: 85,
             spf: { success: true }, dkim: { success: true, selectors_found: [{}] },
             dmarc: { success: true, policy: "reject" }, issues: [], recommendations: [] }
    DnsChecker.stub(:check, { success: false }) do
      EmailChecker.stub(:check, full) do
        res = Tools::EmailAuthCheck.new.execute(domain: "example.com", scope: "bogus")
        assert_equal "B", res.data[:authentication_grade]
        assert_match(/grade B/, res.summary)
      end
    end
  end
end
