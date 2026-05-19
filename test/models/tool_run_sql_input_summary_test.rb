require "test_helper"

class ToolRunSqlInputSummaryTest < ActiveSupport::TestCase
  test "single-line SQL returns the first 80 chars" do
    s = ToolRun.build_input_summary(sql: "SELECT id, domain FROM domains WHERE id = 1")
    assert_equal "SELECT id, domain FROM domains WHERE id = 1", s
  end

  test "multi-line SQL collapses newlines and tabs into single spaces" do
    sql = "SELECT id,\n\tdomain\nFROM domains\nWHERE id = 1"
    s = ToolRun.build_input_summary(sql: sql)
    assert_equal "SELECT id, domain FROM domains WHERE id = 1", s
  end

  test "SQL longer than 80 chars is truncated with an ellipsis" do
    long = "SELECT " + ("x," * 40) + "y FROM t"
    s = ToolRun.build_input_summary(sql: long)
    assert_equal 80, s.length
    assert s.end_with?("…")
  end
end
