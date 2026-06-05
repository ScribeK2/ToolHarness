require "test_helper"
require "tool_harness/result_presenter"

class ToolHarness::ResultPresenterTest < ActiveSupport::TestCase
  def make_run(result_data: {}, issues: [], status: "completed", error: nil)
    ToolRun.create!(
      tool_key: "test_tool",
      tool_name: "Test Tool",
      category: "diagnostics",
      status: status,
      success: status == "completed",
      result_data: result_data,
      issues: issues,
      error: error
    )
  end

  test "returns an empty list for runs with no data and no issues" do
    run = make_run
    assert_equal [], ToolHarness::ResultPresenter.new(run).sections
  end

  test "renders top-level hash keys as sections with kv rows" do
    run = make_run(result_data: {
      "registration" => { "registrar" => "IANA", "created" => "1995-08-14" },
      "nameservers"  => { "ns1" => "a.iana", "ns2" => "b.iana" }
    })
    sections = ToolHarness::ResultPresenter.new(run).sections
    assert_equal ["Registration", "Nameservers"], sections.map(&:title)
    assert_equal({ "registrar" => "IANA", "created" => "1995-08-14" }, sections.first.kvs)
  end

  test "renders scalar top-level values as a single-row section" do
    run = make_run(result_data: { "summary" => "all good" })
    sections = ToolHarness::ResultPresenter.new(run).sections
    assert_equal "Summary", sections.first.title
    assert_equal({ "summary" => "all good" }, sections.first.kvs)
  end

  test "preserves the full value for long strings; truncation is a view concern" do
    long = (1..100).map { |i| "line #{i}" }.join("\n")
    run = make_run(result_data: { "whois" => long })
    section = ToolHarness::ResultPresenter.new(run).sections.first
    assert_equal long, section.kvs["whois"]
  end

  test "appends an Issues section at the end" do
    run = make_run(
      result_data: { "stats" => { "count" => 1 } },
      issues: [{ "severity" => "warning", "title" => "near expiry" }]
    )
    sections = ToolHarness::ResultPresenter.new(run).sections
    assert_equal "Issues", sections.last.title
    assert_equal "warning", sections.last.issues.first["severity"]
  end

  test "Issues section renders even with no issues for completed runs" do
    run = make_run(result_data: { "x" => 1 })
    sections = ToolHarness::ResultPresenter.new(run).sections
    assert_equal "Issues", sections.last.title
    assert_equal [], sections.last.issues
    assert_equal "no issues found.", sections.last.kvs[""]
  end

  test "skips top-level keys whose value is blank (nil, empty string, empty hash/array)" do
    run = make_run(result_data: {
      "registrar"   => "IANA",
      "registrant"  => nil,
      "raw_data"    => "",
      "nameservers" => [],
      "metadata"    => {},
      "summary"     => "ok"
    })
    titles = ToolHarness::ResultPresenter.new(run).sections.map(&:title)
    assert_equal ["Registrar", "Summary", "Issues"], titles
  end

  test "failed runs emit an Error section first and no Issues section" do
    run = make_run(status: "failed", error: "boom")
    sections = ToolHarness::ResultPresenter.new(run).sections
    assert_equal "Error", sections.first.title
    assert_equal "boom", sections.first.kvs["message"]
    refute sections.any? { |s| s.title == "Issues" }
  end

  test "renders an array-of-hashes top-level key as a table section" do
    run = make_run(result_data: {
      "hops" => [
        { "hop" => 1, "host" => "gw.local", "rtt_ms" => 1.2 },
        { "hop" => 2, "host" => "isp.net",  "rtt_ms" => 8.5 }
      ]
    })
    section = ToolHarness::ResultPresenter.new(run).sections.first
    assert_equal "Hops", section.title
    refute_nil section.table
    assert_equal %w[hop host rtt_ms], section.table.columns.map(&:key)
    assert_equal ["Hop", "Host", "Rtt Ms"], section.table.columns.map(&:label)
    assert_equal [true, false, true], section.table.columns.map(&:numeric)
    assert_equal({ "hop" => "1", "host" => "gw.local", "rtt_ms" => "1.2" }, section.table.rows.first)
  end

  test "renders an array-of-scalars top-level key as kv rows, not a table" do
    run = make_run(result_data: { "a_records" => ["1.1.1.1", "2.2.2.2"] })
    section = ToolHarness::ResultPresenter.new(run).sections.first
    assert_nil section.table
    assert_equal({ "[0]" => "1.1.1.1", "[1]" => "2.2.2.2" }, section.kvs)
  end

  test "renders a mixed array (not all hashes) as kv rows, not a table" do
    run = make_run(result_data: { "items" => [{ "a" => 1 }, "loose"] })
    section = ToolHarness::ResultPresenter.new(run).sections.first
    assert_nil section.table
  end

  test "builds table columns from the union of ragged row keys, filling missing cells" do
    run = make_run(result_data: {
      "rows" => [
        { "a" => "x", "b" => "y" },
        { "a" => "z", "c" => "w" }
      ]
    })
    table = ToolHarness::ResultPresenter.new(run).sections.first.table
    assert_equal %w[a b c], table.columns.map(&:key)
    assert_equal({ "a" => "x", "b" => "y", "c" => "—" }, table.rows.first)
    assert_equal({ "a" => "z", "b" => "—", "c" => "w" }, table.rows.last)
  end

  test "formats nested-array cells as comma-joined strings (non-numeric column)" do
    run = make_run(result_data: { "hops" => [{ "rtts" => [1.1, 2.2, 3.3] }] })
    table = ToolHarness::ResultPresenter.new(run).sections.first.table
    assert_equal false, table.columns.first.numeric
    assert_equal "1.1, 2.2, 3.3", table.rows.first["rtts"]
  end
end
