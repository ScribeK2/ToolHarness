require "test_helper"

class ToolHarness::RegistryTest < ActiveSupport::TestCase
  # We don't reset the global registry — instead, we capture the test-local
  # class we add and remove only that entry in teardown. This keeps real
  # tools registered for other parallel test files.
  def teardown
    @added_keys&.each { |k| ToolHarness::Registry.tools.delete(k) }
  end

  # ---- find_tool / lookups against the real registered set ----

  test "find_tool returns the class by symbol or string key" do
    assert_equal Tools::DnsLookup, ToolHarness::Registry.find_tool(:dns_lookup)
    assert_equal Tools::DnsLookup, ToolHarness::Registry.find_tool("dns_lookup")
  end

  test "find_tool returns nil for unknown keys" do
    assert_nil ToolHarness::Registry.find_tool(:nonexistent_tool)
    assert_nil ToolHarness::Registry.find_tool("ghost")
  end

  test "all_categories returns the unique sorted category list" do
    cats = ToolHarness::Registry.all_categories
    assert_includes cats, :dns
    assert_includes cats, :ssl
    assert_includes cats, :email_auth
    assert_includes cats, :diagnostics
    assert_includes cats, :hosting
    assert_includes cats, :domain
    assert_equal cats.sort, cats, "categories should come back sorted"
  end

  test "tools_for_category filters to that category" do
    dns_tools = ToolHarness::Registry.tools_for_category(:dns)
    assert dns_tools.all? { |t| t.category == :dns }
    assert_includes dns_tools, Tools::DnsLookup
    assert_includes dns_tools, Tools::SubdomainScan
  end

  test "tools_for_input filters by input_type" do
    domain_tools = ToolHarness::Registry.tools_for_input(:domain)
    assert domain_tools.all? { |t| t.input_type == :domain }
    assert_includes domain_tools, Tools::DnsLookup
  end

  # ---- register_tool mutation, then clean up ----

  test "register_tool keys a class by demodulized snake_case name" do
    @added_keys = [:test_probe_alpha]

    klass = Class.new
    klass.define_singleton_method(:name) { "Tools::TestProbeAlpha" }
    klass.define_singleton_method(:category) { :test }
    klass.define_singleton_method(:tool_name) { "Test Probe Alpha" }

    ToolHarness::Registry.register_tool(klass)
    assert_equal klass, ToolHarness::Registry.find_tool(:test_probe_alpha)
  end

  test "categories groups tools by category" do
    by_cat = ToolHarness::Registry.categories
    assert by_cat[:dns].present?
    assert by_cat[:ssl].present?
    by_cat.each { |cat, tools| assert tools.all? { |t| t.category == cat } }
  end
end
