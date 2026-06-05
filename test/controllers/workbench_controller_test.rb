require "test_helper"

class WorkbenchControllerTest < ActionDispatch::IntegrationTest
  test "GET /workbench renders the workbench shell with status text" do
    get "/workbench"
    assert_response :success
    assert_match /TOOLHARNESS/, response.body
    assert_match /NORMAL/, response.body
  end

  test "GET /workbench with a tool param highlights the active tool" do
    get "/workbench", params: { tool: "whois_lookup" }
    assert_response :success
  end

  test "rail groups tools by category" do
    get "/workbench"
    assert_match %r{>domain</span>}, response.body
    assert_match /whois_lookup|WHOIS Lookup/i, response.body
  end

  test "active tool is marked with the active rail class" do
    get "/workbench", params: { tool: "whois_lookup" }
    assert_match /data-active="true"/, response.body
  end

  test "view=history renders the filter row and runs table" do
    ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain", status: "completed", success: true, input_summary: "example.com")
    get "/workbench", params: { view: "history" }
    assert_match /name="filter"/, response.body
    assert_match /whois_lookup/, response.body
  end

  test "view=history with a filter narrows the table" do
    ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain", status: "completed", success: true, input_summary: "x.com")
    ToolRun.create!(tool_key: "dns_lookup",   tool_name: "DNS",   category: "dns",    status: "completed", success: true, input_summary: "y.com")
    get "/workbench", params: { view: "history", filter: "tool=whois_lookup" }
    assert_match /x\.com/, response.body
    assert_no_match /y\.com/, response.body
  end

  test "view=history excludes runs that belong to an investigation" do
    ToolRun.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                    status: "completed", success: true, input_summary: "orphan-run.com")

    inv = Investigation.create!(domain: "child-run.com", track: "orientation",
                                status: "completed", verdict_status: "healthy",
                                completed_at: Time.current, findings: [])
    inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns",
                          status: "completed", success: true, step_order: 0,
                          input_summary: "child-run.com")

    get "/workbench", params: { view: "history" }
    assert_response :success
    assert_match(/orphan-run\.com/, response.body)
    assert_no_match(/child-run\.com/, response.body)
  end
end
