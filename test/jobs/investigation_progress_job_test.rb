require "test_helper"

class InvestigationProgressJobTest < ActiveSupport::TestCase
  def make_investigation
    inv = Investigation.create!(domain: "example.com", track: "orientation", status: "running", started_at: Time.current)
    w = inv.tool_runs.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain", status: "completed",
                              success: true, step_order: 0,
                              result_data: { "expiration_date" => (Date.today + 200).iso8601, "nameservers" => ["ns1.foo.com"] })
    d = inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "completed",
                              success: true, step_order: 1,
                              result_data: { "a_records" => ["1.2.3.4"], "ns_records" => ["ns1.foo.com."], "mx_records" => [] })
    h = inv.tool_runs.create!(tool_key: "hosting_diagnostic", tool_name: "Hosting", category: "hosting", status: "completed",
                              success: true, step_order: 2,
                              result_data: { "open_ports" => ["http", "https"] })
    [inv, w, d, h]
  end

  test "correlates and completes when all steps terminal" do
    inv, * = make_investigation
    InvestigationProgressJob.perform_now(inv.id)
    inv.reload

    assert_equal "completed", inv.status
    assert_not_nil inv.completed_at
    assert_equal "issues", inv.verdict_status              # no_mx warning
    assert_includes inv.findings.map { |f| f["code"] }, "no_mx"
    assert_equal "hosting_website", inv.suggested_track    # web up, no MX
  end

  test "does not correlate while a step is still pending" do
    inv, w, * = make_investigation
    w.update_column(:status, "pending")

    InvestigationProgressJob.perform_now(inv.id)
    inv.reload

    assert_equal "running", inv.status
    assert_nil inv.verdict_status
    assert_empty inv.findings
  end

  test "is idempotent: a second run does not re-correlate a completed investigation" do
    inv, * = make_investigation
    InvestigationProgressJob.perform_now(inv.id)
    first_completed_at = inv.reload.completed_at

    InvestigationProgressJob.perform_now(inv.id)
    assert_equal first_completed_at, inv.reload.completed_at
  end
end
