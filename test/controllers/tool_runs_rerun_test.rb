require "test_helper"

class ToolRunsRerunTest < ActionDispatch::IntegrationTest
  def source_run
    ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
  end

  test "POST rerun creates a new pending run with the same input and enqueues the job" do
    src = source_run

    assert_difference -> { ToolRun.count }, 1 do
      assert_enqueued_with(job: ToolRunJob) do
        post tool_run_rerun_path(src)
      end
    end

    run = ToolRun.order(created_at: :desc).first
    assert_not_equal src.id, run.id
    assert_equal "dns_lookup", run.tool_key
    assert_equal "pending", run.status
    assert_equal "example.com", run.input["domain"]
    assert_redirected_to workbench_path(tool: "dns_lookup", target: run.input_summary, run: run.id)
  end

  test "POST rerun with Turbo Stream replaces #result_panel" do
    src = source_run
    post tool_run_rerun_path(src), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/turbo-stream action="replace" target="result_panel"/, response.body)
  end

  test "POST rerun for a missing run returns 404" do
    post tool_run_rerun_path(id: 999_999)
    assert_response :not_found
  end
end
