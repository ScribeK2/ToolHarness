require "test_helper"

class Tools::MailLogAnalyzerTest < ActiveSupport::TestCase
  def run_log(log) = Tools::MailLogAnalyzer.new.execute(log: log)

  test "registers with key mail_log_analyzer in category email" do
    assert_equal Tools::MailLogAnalyzer, ToolHarness::Registry.find_tool(:mail_log_analyzer)
    assert_equal :email, Tools::MailLogAnalyzer.category
    assert_equal({ log: :textarea }, Tools::MailLogAnalyzer.form_fields)
  end

  test "unsuccessful result on unrecognizable input" do
    res = run_log("nothing useful here")
    assert_equal false, res.success
    assert_match(/log lines/i, res.summary)
  end

  test "partial bounce (some delivered, one bounced) produces a string-keyed warning issue" do
    log = <<~LOG
      postfix/smtp[1]: BNC00001: to=<good@example.net>, relay=mx[198.51.100.5]:25, dsn=2.0.0, status=sent (250 OK)
      postfix/smtp[1]: BNC00001: to=<nobody@example.net>, relay=mx[198.51.100.5]:25, dsn=5.1.1, status=bounced (550 5.1.1 User unknown)
    LOG
    res = run_log(log)
    assert res.success
    issue = res.issues.find { |i| i["title"].to_s.include?("bounced") }
    assert issue, "expected a bounce issue"
    assert_equal "warning", issue["severity"]
    assert_match(/mailbox doesn't exist/i, issue["message"])
  end

  test "all-recipient bounce escalates to critical" do
    log = "postfix/smtp[1]: BNC00002: to=<nobody@example.net>, relay=mx[198.51.100.5]:25, dsn=5.1.1, status=bounced (550 5.1.1 User unknown)"
    issue = run_log(log).issues.find { |i| i["title"].to_s.include?("bounced") }
    assert_equal "critical", issue["severity"]
  end

  test "deferred message produces an info issue" do
    log = "postfix/smtp[1]: DEF00001: to=<u@example.org>, relay=mx[192.0.2.7]:25, dsn=4.7.1, status=deferred (451 4.7.1 Greylisting, try again later)"
    issue = run_log(log).issues.find { |i| i["title"].to_s.include?("deferred") }
    assert_equal "info", issue["severity"]
  end

  test "NOQUEUE rejection produces a warning issue" do
    log = "postfix/smtpd[1]: NOQUEUE: reject: RCPT from unknown[185.220.101.1]: 554 5.7.1 blocked using zen.spamhaus.org; from=<s@bad.com> to=<v@ourdomain.com> proto=ESMTP"
    issue = run_log(log).issues.find { |i| i["title"].to_s.match?(/rejected/i) }
    assert_equal "warning", issue["severity"]
  end

  test "clean delivery yields success with no issues and a summary" do
    log = "postfix/smtp[1]: OK000001: to=<r@example.net>, relay=mx[198.51.100.5]:25, dsn=2.0.0, status=sent (250 OK)"
    res = run_log(log)
    assert res.success
    assert_empty res.issues
    assert_match(/1 delivered/i, res.summary)
  end
end
