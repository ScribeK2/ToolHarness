require "test_helper"

class ToolRunRetentionTest < ActiveSupport::TestCase
  test "purge_older_than! deletes runs older than the cutoff" do
    old = ToolRun.create!(tool_key: "x", tool_name: "X", category: "diagnostics",
                          status: "completed", success: true, created_at: 91.days.ago)
    recent = ToolRun.create!(tool_key: "x", tool_name: "X", category: "diagnostics",
                             status: "completed", success: true)
    count = ToolRun.purge_older_than!(90.days)
    assert_equal 1, count
    assert_nil ToolRun.find_by(id: old.id)
    assert ToolRun.exists?(recent.id)
  end

  test "enforce_retention_cap! deletes the oldest beyond the cap" do
    6.times { ToolRun.create!(tool_key: "t", tool_name: "T", category: "diagnostics", status: "completed", success: true) }
    count = ToolRun.enforce_retention_cap!(cap: 4)
    assert_equal 2, count
    assert_equal 4, ToolRun.count
  end
end
