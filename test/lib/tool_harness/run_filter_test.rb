require "test_helper"
require "tool_harness/run_filter"

class ToolHarness::RunFilterTest < ActiveSupport::TestCase
  setup do
    make_run(tool: "whois_lookup", success: true, expires_in: 5)
    make_run(tool: "ssl_inspect",  success: true, expires_in: 60)
    make_run(tool: "dns_lookup",   success: false)
    @scope = ToolRun.all
  end

  def make_run(tool:, success:, expires_in: nil)
    data = {}
    if tool == "whois_lookup" && expires_in
      data["expiration_date"] = (Date.today + expires_in).iso8601
    end
    if tool == "ssl_inspect" && expires_in
      data["certificate"] = { "days_until_expiry" => expires_in }
    end
    ToolRun.create!(
      tool_key: tool, tool_name: tool.humanize, category: "domain",
      status: success ? "completed" : "failed",
      success: success, result_data: data,
      issues: success ? [{ "severity" => "warning", "title" => "x" }] : []
    )
  end

  test "tool= matches exact tool_key" do
    result = ToolHarness::RunFilter.apply(@scope, "tool=whois_lookup")
    assert_equal ["whois_lookup"], result.pluck(:tool_key)
  end

  test "target~ matches input_summary substring" do
    run = ToolRun.first
    run.update!(input_summary: "acme.io")
    result = ToolHarness::RunFilter.apply(@scope, "target~acme")
    assert_includes result, run
  end

  test "status= matches status string" do
    result = ToolHarness::RunFilter.apply(@scope, "status=failed")
    assert_equal [false], result.pluck(:success)
  end

  test "expires<30d matches both whois and ssl runs near expiry" do
    result = ToolHarness::RunFilter.apply(@scope, "expires<30d")
    assert_equal 1, result.size, "only the whois run with 5d expiry should match"
  end

  test "expires<90d picks up the ssl run as well" do
    result = ToolHarness::RunFilter.apply(@scope, "expires<90d")
    assert_equal 2, result.size
  end

  test "multiple tokens AND together" do
    result = ToolHarness::RunFilter.apply(@scope, "tool=whois_lookup status=completed")
    assert_equal ["whois_lookup"], result.pluck(:tool_key)
  end

  test "empty filter returns the scope unchanged" do
    assert_equal @scope.size, ToolHarness::RunFilter.apply(@scope, "").size
  end

  test "today returns runs created today" do
    result = ToolHarness::RunFilter.apply(@scope, "today")
    assert_equal @scope.size, result.size
  end

  test "bad syntax surfaces an error" do
    err = ToolHarness::RunFilter.errors_for("wat???")
    assert err.any?
  end
end
