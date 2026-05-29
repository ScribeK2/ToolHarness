require "test_helper"

class ToolRunPrimaryInputTest < ActiveSupport::TestCase
  test "returns the first form field value from input" do
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
    assert_equal "example.com", run.primary_input
  end

  test "returns first field value even when secondary fields are present" do
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:ssl_inspect),
      params: { domain: "example.com", port: "8443" }
    )
    assert_equal "example.com", run.primary_input
  end

  test "falls back to input_summary when tool_class is unknown" do
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
    run.update_column(:tool_key, "tool_that_no_longer_exists")
    assert_equal run.input_summary, run.primary_input
  end

  test "falls back to input_summary when primary value is blank" do
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
    run.update_column(:input, { "domain" => "" })
    assert_equal run.input_summary, run.primary_input
  end
end
