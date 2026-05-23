require "test_helper"

class Tools::SqlWorkbenchTest < ActiveSupport::TestCase
  test "does not shell out" do
    src = File.read(Rails.root.join("app/services/tools/sql_workbench.rb"))
    refute_match(/Open3/, src)
    refute_match(/\bsystem\s*\(/, src)
    refute_match(/`[^`]*`/m, src)
  end

  test "tool metadata" do
    assert_equal "SQL Workbench", Tools::SqlWorkbench.tool_name
    assert_equal :database,        Tools::SqlWorkbench.category
    assert_equal :sql,             Tools::SqlWorkbench.input_type
    refute Tools::SqlWorkbench.cacheable?
    assert_equal "workbench/sql/pane", Tools::SqlWorkbench.custom_partial
    assert_equal({ sql: :text }, Tools::SqlWorkbench.form_fields)
  end

  test "registry registers under :sql_workbench in the :database category" do
    assert_equal Tools::SqlWorkbench, ToolHarness::Registry.find_tool(:sql_workbench)
    assert_includes ToolHarness::Registry.tools_for_category(:database), Tools::SqlWorkbench
  end
end
