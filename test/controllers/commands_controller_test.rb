require "test_helper"

class CommandsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "cmd@test", password: "password123")
    sign_in @user
  end

  test "POST /commands with :run dispatches a tool run" do
    post "/commands", params: { cmd: "run whois_lookup example.com" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /turbo-stream/, response.body
    assert ToolRun.exists?(user: @user, tool_key: "whois_lookup"), "expected a ToolRun created"
  end

  test "POST /commands with :export returns a stream that points to a downloadable URL" do
    run = ToolRun.create!(user: @user, tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                          status: "completed", success: true, result_data: { "x" => 1 })
    post "/commands", params: { cmd: "export json", run_id: run.id }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /download/i, response.body
  end

  test "POST /commands with an unknown command returns an inline error stream" do
    post "/commands", params: { cmd: "nope" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match /no command/i, response.body
  end
end
