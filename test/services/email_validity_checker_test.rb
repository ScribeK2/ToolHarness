require "test_helper"

class EmailValidityCheckerTest < ActiveSupport::TestCase
  def run_check(email, dns: { mx_records: [{ host: "mx.example.com.", priority: 10 }], a_records: ["1.2.3.4"] }, smtp: :exists)
    c = EmailValidityChecker.new(email)
    DnsChecker.stub(:check, dns) do
      c.stub(:smtp_probe, ->(_h, _e) { smtp }) { c.check }
    end
  end

  def codes(r) = r[:issues].map { |i| i["code"] }

  test "valid, deliverable, mailbox exists -> clean, no issues" do
    r = run_check("user@example.com")
    assert r[:success]
    assert r[:valid_format]
    assert r[:deliverable]
    assert_equal ["mx.example.com"], r[:mx_hosts]
    assert_equal "exists", r[:smtp]
    assert_empty r[:issues]
  end

  test "invalid format -> invalid_format issue and DnsChecker is NOT called" do
    called = false
    c = EmailValidityChecker.new("not-an-email")
    DnsChecker.stub(:check, ->(*) { called = true; { mx_records: [], a_records: [] } }) do
      r = c.check
      assert_not r[:valid_format]
      assert_includes codes(r), "invalid_format"
    end
    assert_not called, "DnsChecker should not be called for an invalid-format address"
  end

  test "no MX or A -> not deliverable, smtp skipped" do
    r = run_check("user@nodns.example", dns: { mx_records: [], a_records: [] })
    assert_not r[:deliverable]
    assert_includes codes(r), "not_deliverable"
    assert_equal "skipped", r[:smtp]
  end

  test "A record only (implicit MX) -> deliverable but smtp skipped (no MX host)" do
    r = run_check("user@aonly.example", dns: { mx_records: [], a_records: ["1.2.3.4"] })
    assert r[:deliverable]
    assert_equal "skipped", r[:smtp]
  end

  test "disposable domain -> disposable warning" do
    r = run_check("user@mailinator.com")
    assert r[:disposable]
    assert_includes codes(r), "disposable"
  end

  test "smtp inconclusive -> info issue" do
    r = run_check("user@example.com", smtp: :inconclusive)
    assert_equal "inconclusive", r[:smtp]
    assert_includes codes(r), "smtp_inconclusive"
  end

  test "smtp not_found -> warning issue" do
    r = run_check("user@example.com", smtp: :not_found)
    assert_includes codes(r), "smtp_no_mailbox"
  end
end
