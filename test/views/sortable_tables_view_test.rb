require "test_helper"

class SortableTablesViewTest < ActionDispatch::IntegrationTest
  test "a generic tool's array-of-hashes result renders a sortable table" do
    run = ToolRun.create!(
      tool_key: "blacklist", tool_name: "Blacklist Check", category: "diagnostics",
      status: "completed", success: true, execution_time: 0.1,
      input_summary: "example.com",
      result_data: {
        "listings" => [
          { "name" => "Spamhaus ZEN", "zone" => "zen.spamhaus.org", "listed" => true, "result" => "127.0.0.2" },
          { "name" => "Barracuda",    "zone" => "b.barracuda.org",  "listed" => true, "result" => "127.0.0.2" }
        ]
      }
    )

    get workbench_path(tool: "blacklist", run: run.id)
    assert_response :success
    assert_select "table[data-controller='sortable-table']" do
      assert_select "th[data-sort-key='name']"
      assert_select "th[data-sort-key='zone']"
      assert_select "td[data-sort-cell='name'][data-copy-value='Spamhaus ZEN'][data-action~='click->copy#copyValue']"
    end
  end
end
