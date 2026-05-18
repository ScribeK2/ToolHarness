require "test_helper"

class ToolRunsControllerTest < ActionDispatch::IntegrationTest
  test "POST creates a pending ToolRun and enqueues ToolRunJob" do
    assert_difference -> { ToolRun.count }, 1 do
      assert_enqueued_with(job: ToolRunJob) do
        post tool_run_create_path(:dns_lookup), params: { tool_run: { domain: "example.com" } }
      end
    end

    run = ToolRun.order(created_at: :desc).first
    assert_equal "dns_lookup", run.tool_key
    assert_equal "pending",    run.status
    assert_equal "example.com", run.input["domain"]
    assert_redirected_to workbench_path(tool: "dns_lookup", target: run.input_summary, run: run.id)
  end

  test "POST with Turbo Stream accept header replaces #result_panel" do
    post tool_run_create_path(:dns_lookup),
      params: { tool_run: { domain: "example.com" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/turbo-stream action="replace" target="result_panel"/, response.body)
  end

  test "POST permits only declared form_fields, ignoring extras" do
    post tool_run_create_path(:dns_lookup),
      params: { tool_run: { domain: "example.com", malicious: "x" } }

    run = ToolRun.order(created_at: :desc).first
    assert_equal({ "domain" => "example.com" }, run.input)
  end

  test "POST to unknown tool_key returns 404" do
    post tool_run_create_path(:nonexistent_tool), params: { tool_run: { domain: "example.com" } }
    assert_response :not_found
  end
end
