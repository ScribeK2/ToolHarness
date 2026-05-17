require "test_helper"

class ToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "GET /tools renders the catalog" do
    get tools_url
    assert_response :success
    assert_select "h1", text: /Tool Catalog/
  end

  test "GET /tools lists every registered tool" do
    get tools_url
    ToolHarness::Registry.tools.each_key do |tool_key|
      assert_select "a[href=?]", tool_path(tool_key), { count: 1 },
        "expected one card linking to /tools/#{tool_key}"
    end
  end

  test "GET /tools/:tool_key renders the form for a known tool" do
    get tool_url(:dns_lookup)
    assert_response :success
    assert_select "h1", text: "DNS Lookup"
    assert_select "form[action=?]", tool_run_create_path(:dns_lookup)
  end

  test "GET /tools/:tool_key returns 404 for an unknown tool" do
    get tool_url(:nonexistent_tool)
    assert_response :not_found
  end

  test "GET /tools requires authentication" do
    sign_out @user
    get tools_url
    assert_redirected_to new_user_session_path
  end

  test "GET /tools/:tool_key requires authentication" do
    sign_out @user
    get tool_url(:dns_lookup)
    assert_redirected_to new_user_session_path
  end
end
