require "test_helper"

class Tools::WebsiteHealthTest < ActiveSupport::TestCase
  def canned(overrides = {})
    {
      success: true, final_url: "https://example.com/", fetched_over: "https",
      status_code: 200, health: "up", title: "Example", is_wordpress: true,
      wordpress_evidence: ["meta_generator"], wp_version: "6.4", wp_json_available: true,
      critical_error: false, maintenance_mode: false, issues: []
    }.merge(overrides)
  end

  test "maps checker output into a successful Result with data and summary" do
    WebsiteHealthChecker.stub(:check, canned) do
      res = Tools::WebsiteHealth.new.execute(domain: "example.com")
      assert res.success
      assert_equal "up", res.data[:health]
      assert_equal "6.4", res.data[:wp_version]
      assert_not_includes res.data.keys, :issues
      assert_not_includes res.data.keys, :success
      assert_match(/WordPress 6\.4/, res.summary)
    end
  end

  test "surfaces unreachable as a failed Result" do
    WebsiteHealthChecker.stub(:check, canned(success: false, health: "unreachable", status_code: nil, error: "timeout", issues: [{ "code" => "site_unreachable" }])) do
      res = Tools::WebsiteHealth.new.execute(domain: "down.example")
      assert_not res.success
      assert_match(/unreachable/i, res.summary)
    end
  end

  test "auto-registers under the :website_health key" do
    assert_equal Tools::WebsiteHealth, ToolHarness::Registry.find_tool(:website_health)
  end
end
