require "test_helper"

class Sql::HistoryControllerTest < ActionDispatch::IntegrationTest
  test "GET history returns last 20 sql_workbench runs as a turbo_stream" do
    25.times do |i|
      ToolRun.create_pending!(tool_class: Tools::SqlWorkbench, params: { sql: "SELECT #{i}" })
    end
    get sql_history_index_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/sql_history_overlay/, response.body)
  end

  test "GET history filters to only sql_workbench" do
    ToolRun.create_pending!(tool_class: Tools::SqlWorkbench, params: { sql: "SELECT 1" })
    ToolRun.create_pending!(tool_class: Tools::DnsLookup,    params: { domain: "example.com" })
    get sql_history_index_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match(/SELECT 1/, response.body)
    refute_match(/example\.com/, response.body)
  end
end
