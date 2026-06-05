require "test_helper"

class BatchTest < ActiveSupport::TestCase
  def batch_with(*specs)
    b = Batch.create!(tool_key: "dns_lookup", status: "running", domain_count: specs.size)
    specs.each_with_index do |s, i|
      b.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns",
                          status: s[:status], success: s.fetch(:success, s[:status] == "completed"),
                          issues: s[:issues] || [], step_order: i)
    end
    b
  end

  test "all_children_terminal? is false while any child is pending" do
    assert_not batch_with({ status: "completed" }, { status: "pending" }).all_children_terminal?
  end

  test "all_children_terminal? is true when all children are terminal" do
    assert batch_with({ status: "completed" }, { status: "failed" }).all_children_terminal?
  end

  test "aggregate counts" do
    b = batch_with(
      { status: "completed", success: true },
      { status: "completed", success: false },
      { status: "failed" },
      { status: "completed", success: true, issues: [{ "severity" => "critical" }] }
    )
    assert_equal 4, b.done_count
    assert_equal 2, b.success_count
    assert_equal 2, b.failure_count
    assert_equal 1, b.total_critical
  end
end
