require "test_helper"

class WorkbenchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "wb@test", password: "password123")
    sign_in @user
  end

  test "GET /workbench renders the workbench shell with status text" do
    get "/workbench"
    assert_response :success
    assert_match /TOOLHARNESS/, response.body
    assert_match /NORMAL/, response.body
  end

  test "GET /workbench with a tool param highlights the active tool" do
    get "/workbench", params: { tool: "whois_lookup" }
    # Tool-name body assertion moves to Task 2.3 once the tool rail renders names.
    assert_response :success
  end

  test "GET /workbench requires authentication" do
    sign_out @user
    get "/workbench"
    assert_redirected_to new_user_session_path
  end

  test "rail groups tools by category" do
    get "/workbench"
    assert_match %r{>domain</span>}, response.body
    assert_match /whois_lookup|WHOIS Lookup/i, response.body
  end

  test "active tool is marked with the active rail class" do
    get "/workbench", params: { tool: "whois_lookup" }
    # Active row has data-active="true"
    assert_match /data-active="true"/, response.body
  end

  test "view=history renders the filter row and runs table" do
    @user.tool_runs.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain", status: "completed", success: true, input_summary: "example.com")
    get "/workbench", params: { view: "history" }
    assert_match /name="filter"/, response.body
    assert_match /whois_lookup/, response.body
  end

  test "view=history with a filter narrows the table" do
    @user.tool_runs.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain", status: "completed", success: true, input_summary: "x.com")
    @user.tool_runs.create!(tool_key: "dns_lookup",   tool_name: "DNS",   category: "dns",    status: "completed", success: true, input_summary: "y.com")
    get "/workbench", params: { view: "history", filter: "tool=whois_lookup" }
    assert_match /x\.com/, response.body
    assert_no_match /y\.com/, response.body
  end

  test "view=history does not leak runs from another user" do
    other = User.create!(email: "wb-other@test", password: "password123")
    other.tool_runs.create!(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                            status: "completed", success: true, input_summary: "secret.example")
    @user.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns",
                            status: "completed", success: true, input_summary: "mine.example")
    get "/workbench", params: { view: "history" }
    assert_match    /mine\.example/,   response.body
    assert_no_match /secret\.example/, response.body
  end
end
