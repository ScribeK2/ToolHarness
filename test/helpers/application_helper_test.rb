require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  def run_for(tool_key)
    ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(tool_key),
      params: { domain: "example.com" }
    )
  end

  def make_run(result_data: {}, issues: [], status: "completed", error: nil, summary: nil)
    ToolRun.create!(
      tool_key: "test_tool",
      tool_name: "Test Tool",
      category: "diagnostics",
      status: status,
      success: status == "completed",
      result_data: result_data,
      issues: issues,
      error: error,
      summary: summary,
      execution_time: 1.2345
    )
  end

  test "ticket text format is unchanged (regression)" do
    run = make_run(summary: "all good",
                   issues: [{ "severity" => "warning", "title" => "Heads up", "message" => "check this" }])
    expected = <<~TEXT.strip
      [Test Tool]
      all good

      Issues (1):
        - [WARNING] Heads up: check this

      Run ##{run.id} · #{run.execution_time.round(3)}s · #{run.created_at.utc.strftime('%Y-%m-%d %H:%M UTC')}
    TEXT
    assert_equal expected, tool_run_ticket_text(run)
  end

  test "full text inserts rendered sections between ticket header and footer" do
    run = make_run(summary: "1 record",
                   result_data: { "records" => { "A" => "93.184.216.34" } })
    text = tool_run_full_text(run)
    assert_includes text, "[Test Tool]\n1 record"
    assert_includes text, "## Records\nA:  93.184.216.34"
    assert_match(/Run #\d+ · [\d.]+s · \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC\z/, text)
  end

  test "full text does not duplicate issues already in the header" do
    run = make_run(summary: "1 issue",
                   result_data: { "note" => "scalar value" },
                   issues: [{ "severity" => "info", "title" => "FYI" }])
    text = tool_run_full_text(run)
    assert_equal 1, text.scan("FYI").size
    refute_includes text, "## Issues"
  end

  test "full text for failed runs equals the ticket text" do
    run = make_run(status: "failed", error: "boom")
    assert_equal tool_run_ticket_text(run), tool_run_full_text(run)
    assert_includes tool_run_full_text(run), "FAILED: boom"
  end

  test "full text for completed runs with no result data equals the ticket text" do
    run = make_run(summary: "nothing to report")
    assert_equal tool_run_ticket_text(run), tool_run_full_text(run)
  end

  test "domain target offers other domain tools and host tools, not itself" do
    keys = sibling_tools_for(run_for(:whois_lookup)).map(&:first)

    assert_includes keys, "dns_lookup"        # sibling domain tool
    assert_includes keys, "hosting_diagnostic" # host tool reachable from a domain
    refute_includes keys, "whois_lookup"      # never itself
  end

  test "host target offers only host tools" do
    keys = sibling_tools_for(run_for(:blacklist)).map(&:first)

    assert_includes keys, "hosting_diagnostic" # another host tool
    refute_includes keys, "dns_lookup"         # domain-only tool excluded
    refute_includes keys, "blacklist"          # never itself
  end

  test "special input types yield no siblings" do
    assert_empty sibling_tools_for(run_for(:bulk_run))
    assert_empty sibling_tools_for(run_for(:sql_workbench))
  end

  test "pairs are [key, display name] sorted by name" do
    pairs = sibling_tools_for(run_for(:whois_lookup))
    names = pairs.map(&:last)
    assert_equal names.sort, names
    pairs.each { |key, name| assert_kind_of String, key; assert_kind_of String, name }
  end
end
