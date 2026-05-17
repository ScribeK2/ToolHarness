require "test_helper"

class ToolRunRetentionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "ret@test", password: "password123")
  end

  test "purge_older_than! deletes runs older than the cutoff" do
    old = @user.tool_runs.create!(tool_key: "x", tool_name: "X", category: "diagnostics",
                                  status: "completed", success: true, created_at: 91.days.ago)
    recent = @user.tool_runs.create!(tool_key: "x", tool_name: "X", category: "diagnostics",
                                     status: "completed", success: true)
    count = ToolRun.purge_older_than!(90.days)
    assert_equal 1, count
    assert_nil ToolRun.find_by(id: old.id)
    assert ToolRun.exists?(recent.id)
  end

  test "enforce_retention_cap! deletes the oldest beyond the cap" do
    # Cap is 5000 in production; force a small cap in test for speed.
    6.times { |i| @user.tool_runs.create!(tool_key: "t", tool_name: "T", category: "diagnostics", status: "completed", success: true) }
    count = ToolRun.enforce_retention_cap!(cap: 4)
    assert_equal 2, count
    assert_equal 4, @user.tool_runs.count
  end
end
