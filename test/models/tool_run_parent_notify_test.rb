require "test_helper"

class ToolRunParentNotifyTest < ActiveJob::TestCase
  test "a batch child flipping to terminal enqueues BatchProgressJob" do
    batch = Batch.create!(tool_key: "dns_lookup", status: "running", domain_count: 1)
    run = batch.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "pending", step_order: 0)
    assert_enqueued_with(job: BatchProgressJob, args: [batch.id]) do
      run.update!(status: "completed", success: true)
    end
  end

  test "an investigation child flipping to terminal still enqueues InvestigationProgressJob (regression)" do
    inv = Investigation.create!(domain: "example.com", track: "orientation", status: "running", started_at: Time.current)
    run = inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "pending", step_order: 0)
    assert_enqueued_with(job: InvestigationProgressJob, args: [inv.id]) do
      run.update!(status: "completed", success: true)
    end
  end

  test "a non-terminal status change enqueues nothing" do
    batch = Batch.create!(tool_key: "dns_lookup", status: "running", domain_count: 1)
    run = batch.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "pending", step_order: 0)
    assert_no_enqueued_jobs only: BatchProgressJob do
      run.update!(status: "processing")
    end
  end
end
