require "test_helper"

class Investigations::StepSchedulerTest < ActiveJob::TestCase
  def email_investigation(dns_data:, dns_success: true)
    inv = Investigation.create!(domain: "example.com", track: "email_delivery", status: "running", started_at: Time.current)
    inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns",
                          status: dns_success ? "completed" : "failed", success: dns_success,
                          step_order: 0, result_data: dns_data)
    inv.tool_runs.create!(tool_key: "blacklist", tool_name: "Blacklist", category: "diagnostics",
                          status: "pending", step_order: 5, input: { "domain" => "example.com" })
    inv
  end

  test "enqueues blacklist against the primary (lowest-priority) MX host" do
    inv = email_investigation(dns_data: { "mx_records" => [
      { "priority" => 20, "host" => "mx2.mail.com." },
      { "priority" => 10, "host" => "mx1.mail.com." }
    ] })
    bl = inv.tool_runs.find_by(tool_key: "blacklist")

    assert_enqueued_with(job: ToolRunJob, args: [bl.id]) do
      Investigations::StepScheduler.new(inv).call
    end

    bl.reload
    assert_equal "processing", bl.status
    assert_equal "mx1.mail.com", bl.input["domain"]  # trailing dot stripped
    assert_equal "mx1.mail.com", bl.input_summary
  end

  test "skips blacklist when DNS returned no MX" do
    inv = email_investigation(dns_data: { "mx_records" => [] })
    assert_no_enqueued_jobs only: ToolRunJob do
      Investigations::StepScheduler.new(inv).call
    end
    bl = inv.tool_runs.find_by(tool_key: "blacklist").reload
    assert_equal "skipped", bl.status
    assert_match(/no mx/i, bl.skip_reason)
  end

  test "skips blacklist when the dns_lookup probe failed" do
    inv = email_investigation(dns_data: {}, dns_success: false)
    Investigations::StepScheduler.new(inv).call
    assert_equal "skipped", inv.tool_runs.find_by(tool_key: "blacklist").reload.status
  end

  test "does nothing while the dependency is still pending" do
    inv = email_investigation(dns_data: { "mx_records" => [{ "priority" => 10, "host" => "m.com." }] })
    inv.tool_runs.find_by(tool_key: "dns_lookup").update_column(:status, "pending")
    assert_no_enqueued_jobs only: ToolRunJob do
      Investigations::StepScheduler.new(inv).call
    end
    assert_equal "pending", inv.tool_runs.find_by(tool_key: "blacklist").reload.status
  end

  test "is idempotent: a second call does not re-enqueue" do
    inv = email_investigation(dns_data: { "mx_records" => [{ "priority" => 10, "host" => "m.com." }] })
    Investigations::StepScheduler.new(inv).call
    assert_no_enqueued_jobs only: ToolRunJob do
      Investigations::StepScheduler.new(inv).call
    end
  end

  test "orientation (no dependents) is a no-op" do
    inv = Investigation.create!(domain: "x.com", track: "orientation", status: "running", started_at: Time.current)
    inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "completed", success: true, step_order: 1)
    assert_no_enqueued_jobs only: ToolRunJob do
      Investigations::StepScheduler.new(inv).call
    end
  end

  test "retargets both hosting_diagnostic and blacklist at the primary MX host" do
    inv = Investigation.create!(domain: "example.com", track: "email_delivery", status: "running", started_at: Time.current)
    inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "completed",
                          success: true, step_order: 0, result_data: { "mx_records" => [{ "priority" => 10, "host" => "mx1.mail.com." }] })
    hosting = inv.tool_runs.create!(tool_key: "hosting_diagnostic", tool_name: "Hosting", category: "hosting",
                                    status: "pending", step_order: 4, input: { "domain" => "example.com" })
    blacklist = inv.tool_runs.create!(tool_key: "blacklist", tool_name: "Blacklist", category: "diagnostics",
                                      status: "pending", step_order: 5, input: { "domain" => "example.com" })

    assert_enqueued_jobs 2, only: ToolRunJob do
      Investigations::StepScheduler.new(inv).call
    end

    assert_equal "mx1.mail.com", hosting.reload.input["domain"]
    assert_equal "mx1.mail.com", blacklist.reload.input["domain"]
    assert_equal "processing", hosting.status
    assert_equal "processing", blacklist.status
  end
end
