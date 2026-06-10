require "test_helper"

# v1.0.0 catalog shape: 15 tools in 8 categories, in rail order.
class ToolRailCategoriesTest < ActiveSupport::TestCase
  EXPECTED = {
    domain:      %i[whois_lookup],
    dns:         %i[dns_lookup historical_dns subdomain_scan],
    web:         %i[ssl_inspect website_inspect page_speed],
    email:       %i[email_auth_check email_validity],
    hosting:     %i[hosting_diagnostic],
    diagnostics: %i[blacklist bulk_run ipinfo],
    database:    %i[sql_workbench],
    config:      %i[credentials]
  }.freeze

  test "every category contains exactly the expected tools" do
    by_cat = ToolHarness::Registry.categories
    EXPECTED.each do |cat, keys|
      actual = (by_cat[cat] || []).map { |k| k.name.demodulize.underscore.to_sym }.sort
      assert_equal keys.sort, actual, "category #{cat}"
    end
    assert_empty ToolHarness::Registry.tools.values.map(&:category).uniq - EXPECTED.keys,
                 "unexpected extra categories"
  end

  test "catalog is exactly 15 tools" do
    assert_equal 15, ToolHarness::Registry.tools.size
  end
end
