require "test_helper"

class Investigations::ReportGeneratorTest < ActiveSupport::TestCase
  def completed_investigation
    inv = Investigation.create!(
      domain: "example.com", track: "orientation", status: "completed",
      ticket_ref: "TCK-9", verdict_status: "issues",
      suggested_track: "email_delivery", completed_at: Time.current,
      findings: [
        { "severity" => "warning", "code" => "no_mx", "title" => "Mail not configured",
          "message" => "No MX records found.", "provenance" => ["dns_lookup"],
          "recommendation" => "Add MX records." }
      ]
    )
    inv.tool_runs.create!(tool_key: "whois_lookup", tool_name: "WHOIS Lookup", category: "domain",
                          status: "completed", success: true, step_order: 0, summary: "Registered via GoDaddy.")
    inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS Lookup", category: "dns",
                          status: "completed", success: true, step_order: 1, summary: "Resolves to 1.2.3.4.")
    inv
  end

  test "renders header with domain, ticket, verdict" do
    md = Investigations::ReportGenerator.new(completed_investigation).to_markdown
    assert_match(/# Investigation — example\.com/, md)
    assert_match(/Ticket:\*\* TCK-9/, md)
    assert_match(/Verdict:\*\* ISSUES/, md)
  end

  test "renders ranked findings with recommendation" do
    md = Investigations::ReportGenerator.new(completed_investigation).to_markdown
    assert_match(/Mail not configured/, md)
    assert_match(/Add MX records\./, md)
  end

  test "always includes the visibility boundary section" do
    md = Investigations::ReportGenerator.new(completed_investigation).to_markdown
    assert_match(/## Visibility boundary/, md)
    assert_match(/Could not observe/, md)
    assert_match(/registry back-end/, md)         # always-gated box
    assert_match(/mail server/, md)               # named because a mail finding is present
  end

  test "renders probe evidence per step" do
    md = Investigations::ReportGenerator.new(completed_investigation).to_markdown
    assert_match(/WHOIS Lookup/, md)
    assert_match(/Resolves to 1\.2\.3\.4\./, md)
  end

  test "boundary section names the mail server for the email_delivery track" do
    inv = Investigation.create!(domain: "example.com", track: "email_delivery", status: "completed",
                                started_at: 1.minute.ago, completed_at: Time.current,
                                verdict_status: "healthy", findings: [])
    md = Investigations::ReportGenerator.new(inv).to_markdown
    assert_match(/mail server internals/i, md)
    assert_match(/Graylog/, md)
  end

  test "boundary section names the container and app/PHP layer for hosting_website" do
    inv = Investigation.create!(domain: "example.com", track: "hosting_website", status: "completed",
                                started_at: 1.minute.ago, completed_at: Time.current,
                                verdict_status: "critical",
                                findings: [{ "severity" => "critical", "code" => "wp_critical_error",
                                             "title" => "WordPress critical error", "message" => "boom",
                                             "provenance" => ["website_inspect"], "recommendation" => "check logs" }])
    md = Investigations::ReportGenerator.new(inv).to_markdown
    assert_match(/Pterodactyl container internals/i, md)
    assert_match(/application\/PHP layer/i, md)
  end

  test "evidence section marks a skipped probe as SKIPPED with its reason" do
    inv = Investigation.create!(domain: "example.com", track: "email_delivery", status: "completed",
                                started_at: 1.minute.ago, completed_at: Time.current,
                                verdict_status: "critical", findings: [])
    inv.tool_runs.create!(tool_key: "blacklist", tool_name: "Blacklist Check", category: "diagnostics",
                          status: "skipped", skip_reason: "No MX records — reputation check skipped", step_order: 5)
    md = Investigations::ReportGenerator.new(inv).to_markdown
    assert_match(/Blacklist Check \(SKIPPED\)/, md)
    assert_match(/No MX records/, md)
  end
end
