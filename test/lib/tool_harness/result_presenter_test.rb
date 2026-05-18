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
end
