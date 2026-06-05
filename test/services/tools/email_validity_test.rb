require "test_helper"

class Tools::EmailValidityTest < ActiveSupport::TestCase
  RAW = { success: true, email: "user@example.com", local: "user", domain: "example.com",
          valid_format: true, deliverable: true, mx_hosts: ["mx.example.com"],
          disposable: false, smtp: "exists", smtp_detail: "ok",
          issues: [{ "severity" => "info", "code" => "x" }], error: nil }.freeze

  test "maps checker output into a Result (data omits issues/success, issues passed through)" do
    EmailValidityChecker.stub(:check, RAW) do
      res = Tools::EmailValidity.new.execute(email: "user@example.com")
      assert res.success
      assert_equal true, res.data[:deliverable]
      assert_equal ["mx.example.com"], res.data[:mx_hosts]
      assert_not res.data.key?(:issues)
      assert_not res.data.key?(:success)
      assert_equal 1, res.issues.size
      assert_match(/valid format/i, res.summary)
    end
  end

  test "invalid-format result -> summary says invalid" do
    bad = RAW.merge(valid_format: false, issues: [{ "severity" => "critical", "code" => "invalid_format" }])
    EmailValidityChecker.stub(:check, bad) do
      res = Tools::EmailValidity.new.execute(email: "nope")
      assert_match(/invalid email format/i, res.summary)
    end
  end

  test "registered under :email_validity" do
    assert_equal Tools::EmailValidity, ToolHarness::Registry.find_tool(:email_validity)
  end
end
