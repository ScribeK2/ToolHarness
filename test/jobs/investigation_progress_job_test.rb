require "test_helper"

class InvestigationProgressJobTest < ActiveJob::TestCase
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

  def email_investigation(blacklist_status:, dns_mx: [{ "priority" => 10, "host" => "mx.example.com." }], blacklist_data: {})
    inv = Investigation.create!(domain: "example.com", track: "email_delivery", status: "running", started_at: Time.current)
    inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "completed",
                          success: true, step_order: 0, result_data: { "mx_records" => dns_mx })
    spf_data   = { "all_mechanism" => { "qualifier" => "~" } }
    dkim_data  = { "selectors_found" => [{ "selector" => "default", "parsed" => { "flags" => "" } }] }
    dmarc_data = { "policy" => "quarantine" }
    [["spf_check", spf_data], ["dkim_check", dkim_data], ["dmarc_check", dmarc_data]].each_with_index do |(k, rd), i|
      inv.tool_runs.create!(tool_key: k, tool_name: k, category: "email_auth", status: "completed",
                            success: true, step_order: i + 1, result_data: rd)
    end
    inv.tool_runs.create!(tool_key: "hosting_diagnostic", tool_name: "Hosting", category: "hosting", status: "completed",
                          success: true, step_order: 4, result_data: { "open_ports" => ["smtp"] })
    bl = inv.tool_runs.create!(tool_key: "blacklist", tool_name: "Blacklist", category: "diagnostics",
                               status: blacklist_status, step_order: 5, input: { "domain" => "example.com" },
                               result_data: blacklist_data, success: blacklist_status == "completed")
    [inv, bl]
  end

  test "schedules the pending blacklist step instead of correlating" do
    inv, bl = email_investigation(blacklist_status: "pending")

    assert_enqueued_with(job: ToolRunJob, args: [bl.id]) do
      InvestigationProgressJob.perform_now(inv.id)
    end

    assert_equal "running", inv.reload.status          # not correlated — blacklist now processing
    assert_equal "processing", bl.reload.status
    assert_equal "mx.example.com", bl.input["domain"]  # retargeted at the primary MX host
  end

  test "correlates once the scheduled blacklist has completed" do
    inv, _bl = email_investigation(blacklist_status: "completed", blacklist_data: { "listings" => [] })

    InvestigationProgressJob.perform_now(inv.id)

    assert_equal "completed", inv.reload.status
    assert_equal "healthy", inv.verdict_status
  end

  test "correlates after the blacklist is skipped for a no-MX domain" do
    inv, bl = email_investigation(blacklist_status: "pending", dns_mx: [])

    InvestigationProgressJob.perform_now(inv.id)

    assert_equal "skipped", bl.reload.status
    assert_equal "completed", inv.reload.status
    assert_includes inv.findings.map { |f| f["code"] }, "no_mx"
  end
end
