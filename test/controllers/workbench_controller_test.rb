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
end
