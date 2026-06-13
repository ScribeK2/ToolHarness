require "test_helper"

# Runs recorded by retired tools (keys no longer in the registry) must stay
# viewable: custom partial where mapped, generic sections otherwise, and no
# re-run affordance (the tool class is gone).
class LegacyRunViewTest < ActionDispatch::IntegrationTest
  def legacy_run(tool_key:, tool_name:, result_data:)
    ToolRun.create!(
      tool_key: tool_key, tool_name: tool_name, category: "legacy",
      input_type: "domain", input: { "domain" => "example.com" },
      input_summary: "example.com", status: "completed", success: true,
      execution_time: 0.1, result_data: result_data, issues: [], recommendations: []
    )
  end

  test "retired dns_propagation run renders via its legacy partial" do
    run = legacy_run(
      tool_key: "dns_propagation", tool_name: "DNS Propagation",
      result_data: {
        "domain" => "example.com", "record_type" => "A",
        "consensus" => { "value" => ["93.184.216.34"], "count" => 1, "total" => 1 },
        "dissenters" => [], "failures" => [],
        "resolvers" => [{ "ip" => "1.1.1.1", "operator" => "Cloudflare", "status" => "ok",
                          "values" => ["93.184.216.34"], "ttl" => 300, "latency_ms" => 12 }]
      }
    )
    get workbench_path(run: run.id)
    assert_response :success
    assert_select "td[data-copy-value='1.1.1.1']"
  end

  test "retired run without a legacy partial renders generic sections without raising" do
    run = legacy_run(
      tool_key: "traceroute", tool_name: "Traceroute",
      result_data: { "target" => "example.com", "hops" => [] }
    )
    get workbench_path(run: run.id)
    assert_response :success
  end

  test "retired runs show no re-run button" do
    run = legacy_run(tool_key: "traceroute", tool_name: "Traceroute",
                     result_data: { "target" => "example.com", "hops" => [] })
    get workbench_path(run: run.id)
    assert_select "form[action='#{tool_run_rerun_path(run)}']", false
  end
end
