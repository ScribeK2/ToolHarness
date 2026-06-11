require "test_helper"
require "tool_harness/result_presenter"
require "tool_harness/section_text_renderer"

class ToolHarness::SectionTextRendererTest < ActiveSupport::TestCase
  Section = ToolHarness::ResultPresenter::Section
  Table   = ToolHarness::ResultPresenter::Table
  Column  = ToolHarness::ResultPresenter::Column

  def render(*sections)
    ToolHarness::SectionTextRenderer.new(sections).to_text
  end

  test "empty sections render to an empty string" do
    assert_equal "", ToolHarness::SectionTextRenderer.new([]).to_text
  end

  test "kv keys are padded to the longest key in the section" do
    text = render(Section.new(title: "Registration",
                              kvs: { "registrar" => "Tucows", "created" => "2001-03-14" }))
    assert_equal <<~TEXT.strip, text
      ## Registration
      registrar:  Tucows
      created:    2001-03-14
    TEXT
  end

  test "multi-line values are indented under the value column" do
    text = render(Section.new(title: "Raw", kvs: { "block" => "line one\nline two" }))
    assert_equal <<~TEXT.strip, text
      ## Raw
      block:  line one
              line two
    TEXT
  end

  test "all-index-keyed kvs emit bare values, one per line" do
    text = render(Section.new(title: "Name Servers",
                              kvs: { "[0]" => "ns1.example.net", "[1]" => "ns2.example.net" }))
    assert_equal <<~TEXT.strip, text
      ## Name Servers
      ns1.example.net
      ns2.example.net
    TEXT
  end

  test "tables pad columns to the widest cell and right-align numeric columns" do
    table = Table.new(
      columns: [Column.new(key: "type", label: "Type", numeric: false),
                Column.new(key: "ttl",  label: "TTL",  numeric: true)],
      rows: [{ "type" => "A",     "ttl" => "300" },
             { "type" => "CNAME", "ttl" => "60" }]
    )
    text = render(Section.new(title: "Records", table: table))
    assert_equal <<~TEXT.strip, text
      ## Records
      Type   TTL
      A      300
      CNAME   60
    TEXT
  end

  test "issues render as severity-tagged bullet lines" do
    text = render(Section.new(title: "Issues", issues: [
      { "severity" => "warning", "title" => "Privacy proxy", "message" => "registrant hidden" },
      { "severity" => "info", "title" => "All good" }
    ]))
    assert_equal <<~TEXT.strip, text
      ## Issues
      - [WARNING] Privacy proxy: registrant hidden
      - [INFO] All good
    TEXT
  end

  test "sections are joined by blank lines and bodiless sections are skipped" do
    text = render(
      Section.new(title: "One", kvs: { "a" => "1" }),
      Section.new(title: "Empty"),
      Section.new(title: "Two", kvs: { "b" => "2" })
    )
    assert_equal "## One\na:  1\n\n## Two\nb:  2", text
  end
end
