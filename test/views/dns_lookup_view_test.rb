require "test_helper"

class DnsLookupViewTest < ActionDispatch::IntegrationTest
  test "workbench shows record_type select when DnsLookup is selected" do
    get "/workbench", params: { tool: "dns_lookup" }
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
    assert_select "select[name='tool_run[depth]']" do
      assert_select "option[value='quick']"
      assert_select "option[value='worldwide']"
    end
  end

  test "workbench domain input has domain-normalizer controller for dns_lookup" do
    get "/workbench", params: { tool: "dns_lookup" }
    assert_select "input[data-controller~=domain-normalizer][name='tool_run[domain]']"
  end

  test "resolver and value cells are click-to-copy" do
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com", depth: "worldwide", record_type: "A" }
    )
    run.update!(
      status: "completed", success: true, execution_time: 0.2,
      result_data: {
        "domain" => "example.com", "record_type" => "A",
        "consensus" => { "value" => ["93.184.216.34"], "count" => 1, "total" => 1 },
        "dissenters" => [], "failures" => [],
        "resolvers" => [
          { "ip" => "1.1.1.1", "operator" => "Cloudflare", "status" => "ok",
            "values" => ["93.184.216.34"], "ttl" => 300, "latency_ms" => 12 }
        ]
      }
    )

    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_response :success
    assert_select "td[data-copy-value='1.1.1.1'][data-action~='click->copy#copyValue']"
    assert_select "td[data-copy-value='93.184.216.34'][data-action~='click->copy#copyValue']"
  end
end
