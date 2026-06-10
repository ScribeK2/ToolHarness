require "test_helper"

class WorkbenchRetiredToolsTest < ActionDispatch::IntegrationTest
  ABSORBED = {
    "spf_check" => "email_auth_check", "dkim_check" => "email_auth_check",
    "dmarc_check" => "email_auth_check", "dns_propagation" => "dns_lookup",
    "ping" => "hosting_diagnostic", "website_health" => "website_inspect",
    "http_inspect" => "website_inspect"
  }.freeze

  ABSORBED.each do |old_key, new_key|
    test "#{old_key} deep link redirects to #{new_key} preserving target" do
      get workbench_path(tool: old_key, target: "example.com")
      assert_redirected_to workbench_path(tool: new_key, target: "example.com")
    end
  end

  test "cut tools redirect to the workbench root" do
    get workbench_path(tool: "ticket_lookup")
    assert_redirected_to workbench_path
    get workbench_path(tool: "traceroute")
    assert_redirected_to workbench_path
  end

  test "live tool keys do not redirect" do
    get workbench_path(tool: "dns_lookup", target: "example.com")
    assert_response :success
  end
end
