require "application_system_test_case"

class MailLogAnalyzerTest < ApplicationSystemTestCase
  BOUNCE_LOG = <<~LOG
    2026-06-12T02:26:20Z mail01 postfix/qmgr[2790]: B0UNC301: from=<sender@client.com>, size=900, nrcpt=1 (queue active)
    2026-06-12T02:26:21Z mail01 postfix/smtp[2820]: B0UNC301: to=<nobody@example.net>, relay=mx.example.net[198.51.100.5]:25, dsn=5.1.1, status=bounced (host mx.example.net said: 550 5.1.1 <nobody@example.net>: Recipient address rejected: User unknown)
  LOG

  test "mail log analyzer renders a textarea primary input" do
    visit workbench_path(tool: "mail_log_analyzer")
    assert_selector "textarea[name='tool_run[log]']"
  end

  test "mail log analyzer: paste bounced delivery log -> verdict, decoded reason, findings" do
    visit workbench_path(tool: "mail_log_analyzer")
    fill_in "tool_run[log]", with: BOUNCE_LOG
    click_button "RUN"
    assert_text "BOUNCED", wait: 15
    assert_text "Recipient mailbox doesn't exist"
    assert_text "[FINDINGS]"
  end
end
