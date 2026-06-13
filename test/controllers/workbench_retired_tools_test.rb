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

  test "retired-key history link redirects with the run preserved and renders the legacy result" do
    run = ToolRun.create!(
      tool_key: "dns_propagation", tool_name: "DNS Propagation", category: "legacy",
      input_type: "domain", input: { "domain" => "example.com" },
      input_summary: "example.com", status: "completed", success: true,
      execution_time: 0.1, issues: [], recommendations: [],
      result_data: {
        "domain" => "example.com", "record_type" => "A",
        "consensus" => { "value" => ["1.2.3.4"], "count" => 1, "total" => 1 },
        "dissenters" => [], "failures" => [],
        "resolvers" => [{ "ip" => "1.1.1.1", "operator" => "Cloudflare", "status" => "ok",
                           "values" => ["1.2.3.4"], "ttl" => 300, "latency_ms" => 12 }]
      }
    )
    get workbench_path(tool: "dns_propagation", target: "example.com", run: run.id)
    assert_redirected_to workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    follow_redirect!
    assert_response :success
    assert_select "td[data-copy-value='1.1.1.1']"
  end
end
