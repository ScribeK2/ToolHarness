require "test_helper"

class BatchProgressJobTest < ActiveSupport::TestCase
  def child(batch, status)
    batch.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns",
                            status: status, success: status == "completed", step_order: batch.tool_runs.count)
  end

  test "completes the batch when all children are terminal" do
    b = Batch.create!(tool_key: "dns_lookup", status: "running", domain_count: 2)
    child(b, "completed"); child(b, "failed")
    BatchProgressJob.perform_now(b.id)
    assert_equal "completed", b.reload.status
    assert_not_nil b.completed_at
  end

  test "leaves the batch running while a child is still pending" do
    b = Batch.create!(tool_key: "dns_lookup", status: "running", domain_count: 2)
    child(b, "completed"); child(b, "pending")
    BatchProgressJob.perform_now(b.id)
    assert_equal "running", b.reload.status
  end

  test "is idempotent on an already-completed batch" do
    b = Batch.create!(tool_key: "dns_lookup", status: "running", domain_count: 1)
    child(b, "completed")
    BatchProgressJob.perform_now(b.id)
    completed_at = b.reload.completed_at
    BatchProgressJob.perform_now(b.id)
    assert_equal completed_at, b.reload.completed_at
  end
end
