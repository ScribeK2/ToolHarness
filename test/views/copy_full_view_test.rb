require "test_helper"

class CopyFullViewTest < ActionDispatch::IntegrationTest
  def completed_run
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
    run.update!(
      status: "completed", success: true,
      result_data: { "records" => { "A" => "93.184.216.34" } },
      execution_time: 0.12, summary: "1 record"
    )
    run
  end

  test "completed runs embed the full text in a template and expose it on window" do
    run = completed_run
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_response :success
    template = css_select("template#full_tool_run_#{run.id}")
    assert_equal 1, template.size
    assert_includes template.first.text, "## Records"
    assert_includes response.body, "window.toolRunFullText"
  end

  test "result header has a copy full button" do
    run = completed_run
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_select "button[data-controller~=copy][data-action~='click->copy#copyFull']",
                  text: "[y F] copy full"
  end

  test "pending runs embed no full-text template" do
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_select "template[id^=full_]", false
  end

  test "failed runs embed a full-text template that degrades to the ticket text" do
    run = ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(:dns_lookup),
      params: { domain: "example.com" }
    )
    run.update!(status: "failed", success: false, error: "boom")
    get workbench_path(tool: "dns_lookup", target: "example.com", run: run.id)
    assert_response :success
    template = css_select("template#full_tool_run_#{run.id}")
    assert_equal 1, template.size
    assert_includes template.first.text, "FAILED: boom"
  end
end
