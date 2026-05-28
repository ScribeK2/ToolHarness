# test/views/dns_propagation_view_test.rb
require "test_helper"

class DnsPropagationViewTest < ActionDispatch::IntegrationTest
  test "workbench shows record_type select when DnsPropagation is selected" do
    get "/workbench", params: { tool: "dns_propagation" }
    assert_response :success
    assert_select "select[name='tool_run[record_type]']" do
      assert_select "option[value='A']"
      assert_select "option[value='AAAA']"
      assert_select "option[value='MX']"
      assert_select "option[value='NS']"
      assert_select "option[value='CNAME']"
      assert_select "option[value='TXT']"
      assert_select "option[value='SOA']"
      assert_select "option[value='CAA']"
    end
  end

  test "workbench domain input has domain-normalizer controller for dns_propagation" do
    get "/workbench", params: { tool: "dns_propagation" }
    assert_select "input[data-controller~=domain-normalizer][name='tool_run[domain]']"
  end
end
