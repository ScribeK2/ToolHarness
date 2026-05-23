require "test_helper"

class WorkbenchControllerCustomPartialTest < ActionDispatch::IntegrationTest
  test "tools without #custom_partial render the standard target_row" do
    get workbench_path(tool: "dns_lookup")
    assert_response :success
    assert_select "form[action*='dns_lookup']"
  end

  test "tools that define custom_partial expose @custom_partial on the controller" do
    klass = Class.new do
      def self.name          = "ToolHarness::Tools::ProbeOne"
      def self.tool_name     = "Probe One"
      def self.category      = :diagnostics
      def self.custom_partial = "workbench/sql/pane"
      def self.form_fields   = {}
    end
    ToolHarness::Registry.tools[:probe_one] = klass

    get workbench_path(tool: "probe_one")
    assert_response :success
    assert_equal "workbench/sql/pane", @controller.instance_variable_get(:@custom_partial)
  ensure
    ToolHarness::Registry.tools.delete(:probe_one)
  end
end
