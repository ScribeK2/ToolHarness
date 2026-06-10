require "test_helper"

class Tools::WebsiteInspectTest < ActiveSupport::TestCase
  def canned(overrides = {})
    {
      success: true, domain: "example.com", final_url: "https://example.com/",
      fetched_over: "https", status_code: 200, response_time_ms: 120, health: "up",
      title: "Example", https_response: { success: true, status_code: 200 },
      http_response: { success: true, status_code: 301 }, redirects_to_https: true,
      security_headers: {}, missing_headers: [], server_info: { server: "nginx" },
      is_wordpress: true, wordpress_evidence: ["meta_generator"], wp_version: "6.4",
      wp_json_available: true, critical_error: false, maintenance_mode: false, issues: []
    }.merge(overrides)
  end

  test "static metadata" do
    assert_equal "Website Inspection", Tools::WebsiteInspect.tool_name
    assert_equal :domain, Tools::WebsiteInspect.input_type
    assert Tools::WebsiteInspect.preserve_path_in_input?
    refute Tools::WebsiteInspect.cacheable?
  end

  test "registered under :website_inspect; predecessors are gone" do
    assert_equal Tools::WebsiteInspect, ToolHarness::Registry.find_tool(:website_inspect)
    assert_nil ToolHarness::Registry.find_tool(:website_health)
    assert_nil ToolHarness::Registry.find_tool(:http_inspect)
  end

  test "maps inspector output into a successful Result" do
    WebsiteInspector.stub(:check, canned) do
      res = Tools::WebsiteInspect.new.execute(domain: "example.com")
      assert res.success
      assert_equal "up", res.data[:health]
      assert_not_includes res.data.keys, :issues
      assert_not_includes res.data.keys, :success
      assert_match(/HTTPS 200 in 120ms/, res.summary)
      assert_match(/WordPress 6\.4/, res.summary)
      assert_match(/redirect ok/, res.summary)
    end
  end

  test "summary surfaces missing headers, critical error, maintenance" do
    WebsiteInspector.stub(:check, canned(missing_headers: %w[Strict-Transport-Security X-Frame-Options],
                                         critical_error: true, maintenance_mode: true,
                                         redirects_to_https: false)) do
      res = Tools::WebsiteInspect.new.execute(domain: "example.com")
      assert_match(/critical error/, res.summary)
      assert_match(/maintenance mode/, res.summary)
      assert_match(/no HTTP→HTTPS redirect/, res.summary)
      assert_match(/2 missing security headers/, res.summary)
    end
  end

  test "unreachable site is a failed Result" do
    WebsiteInspector.stub(:check, canned(success: false, health: "unreachable",
                                         status_code: nil, error: "timeout",
                                         issues: [{ "code" => "site_unreachable" }])) do
      res = Tools::WebsiteInspect.new.execute(domain: "down.example")
      assert_not res.success
      assert_match(/unreachable/i, res.summary)
    end
  end
end
