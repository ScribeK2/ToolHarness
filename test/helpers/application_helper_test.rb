require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  def run_for(tool_key)
    ToolRun.create_pending!(
      tool_class: ToolHarness::Registry.find_tool(tool_key),
      params: { domain: "example.com" }
    )
  end

  test "domain target offers other domain tools and host tools, not itself" do
    keys = sibling_tools_for(run_for(:whois_lookup)).map(&:first)

    assert_includes keys, "dns_lookup"   # sibling domain tool
    assert_includes keys, "ping"         # host tool reachable from a domain
    refute_includes keys, "whois_lookup" # never itself
  end

  test "host target offers only host tools" do
    keys = sibling_tools_for(run_for(:ping)).map(&:first)

    assert_includes keys, "blacklist"    # another host tool
    refute_includes keys, "dns_lookup"   # domain-only tool excluded
    refute_includes keys, "ping"         # never itself
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
