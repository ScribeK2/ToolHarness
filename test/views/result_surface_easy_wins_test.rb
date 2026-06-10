require "test_helper"

class ResultSurfaceEasyWinsTest < ActionDispatch::IntegrationTest
  # Render a completed run into the workbench result panel.
  def completed_run
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
    run.update!(
      status: "completed", success: true,
      result_data: { "records" => { "A" => "93.184.216.34" } },
      execution_time: 0.12, summary: "1 record"
    )
    run
  end

  test "pending runs carry the run-poller fallback (broadcast-race guard)" do
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_response :success
    assert_select "[data-controller~=run-poller][data-run-poller-url-value='#{tool_run_path(run)}']"
  end

  test "completed runs carry no run-poller" do
    run = completed_run
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_select "[data-controller~=run-poller]", false
  end

  test "kv values are click-to-copy with the full value" do
    run = completed_run
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_response :success
    assert_select "[data-controller~=copy][data-action~='click->copy#copyValue'][data-copy-value='93.184.216.34']"
  end

  test "result header has a re-run button posting to the rerun route" do
    run = completed_run
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_response :success
    assert_select "form[action='#{tool_run_rerun_path(run)}'][method=post] button", text: /re-run/i
  end

  test "result header offers a handoff menu to sibling tools with target prefilled" do
    run = completed_run # dns_lookup, domain example.com
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_response :success

    assert_select "details" do
      assert_select "a[href=?]", workbench_path(tool: "whois_lookup", target: "example.com")
      assert_select "a[href=?]", workbench_path(tool: "hosting_diagnostic", target: "example.com")
    end
    # never links back to the current tool
    assert_select "details a[href*='tool=dns_lookup']", false
  end

  test "history rows have a per-row re-run button" do
    run = completed_run
    get workbench_path(view: "history")
    assert_response :success
    assert_select "form[action='#{tool_run_rerun_path(run)}'][method=post] button"
  end

  test "history rows for a retired-key run show no re-run form" do
    legacy_run = ToolRun.create!(
      tool_key: "dns_propagation", tool_name: "DNS Propagation", category: "legacy",
      input_type: "domain", input: { "domain" => "example.com" },
      input_summary: "example.com", status: "completed", success: true,
      execution_time: 0.1, issues: [], recommendations: [],
      result_data: {}
    )
    get workbench_path(view: "history")
    assert_response :success
    assert_select "form[action='#{tool_run_rerun_path(legacy_run)}']", false
  end
end
