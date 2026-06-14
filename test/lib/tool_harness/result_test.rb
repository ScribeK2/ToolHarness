require "test_helper"

class ToolHarness::ResultTest < ActiveSupport::TestCase
  test "defaults are sensible" do
    r = ToolHarness::Result.new(success: true)
    assert r.success?
    assert_equal({}, r.data)
    assert_equal [], r.issues
    assert_equal [], r.recommendations
    assert_nil r.summary
    assert_nil r.error
    assert_equal false, r.cached
    assert_not_nil r.checked_at
  end

  test "issue severity filters" do
    r = ToolHarness::Result.new(
      success: true,
      issues: [
        { severity: "critical", title: "Critical 1" },
        { severity: "warning",  title: "Warning 1" },
        { severity: "info",     title: "Info 1" },
        { severity: "critical", title: "Critical 2" }
      ]
    )

    assert_equal 2, r.critical_issues.size
    assert_equal 1, r.warnings.size
    assert_equal 1, r.info_issues.size
    assert r.has_issues?
  end

  test "has_issues? false when issues array is empty" do
    r = ToolHarness::Result.new(success: true, issues: [])
    assert_not r.has_issues?
  end

  test "to_h round-trips through JSON" do
    r = ToolHarness::Result.new(
      success: false,
      tool: "Test",
      data: { foo: 1 },
      issues: [{ severity: "critical", title: "x" }],
      error: "boom",
      execution_time: 0.42
    )

    h = r.to_h
    assert_equal false, h[:success]
    assert_equal "Test", h[:tool]
    assert_equal({ foo: 1 }, h[:data])
    assert_equal 1, h[:issues].size
    assert_equal "boom", h[:error]
    assert_equal 0.42, h[:execution_time]

    # JSON round-trip survives
    decoded = JSON.parse(r.to_json)
    assert_equal "Test", decoded["tool"]
    assert_equal "boom", decoded["error"]
  end

  test "success? returns boolean even when initialized with truthy/falsy values" do
    assert_equal true, ToolHarness::Result.new(success: "yes").success?
    assert_equal false, ToolHarness::Result.new(success: nil).success?
    assert_equal false, ToolHarness::Result.new(success: false).success?
  end

  test "severity helpers recognize both string-keyed and symbol-keyed issues" do
    issues = [
      { "severity" => "critical", "title" => "string crit" },
      { severity: "critical", title: "symbol crit" },
      { "severity" => "warning", "title" => "string warn" },
      { severity: "info", title: "symbol info" }
    ]
    res = ToolHarness::Result.new(success: true, tool: "t", issues: issues)
    assert_equal 2, res.critical_issues.size
    assert_equal 1, res.warnings.size
    assert_equal 1, res.info_issues.size
  end
end
