require "test_helper"

class Investigations::HostingWebsiteCorrelatorTest < ActiveSupport::TestCase
  def run_for(key, data: {}, success: true, issues: [], status: nil)
    ToolRun.new(tool_key: key, tool_name: key, category: "hosting",
                input: { "domain" => "example.com" },
                status: status || (success ? "completed" : "failed"),
                success: success, result_data: data, issues: issues)
  end

  def healthy_runs
    [
      run_for("dns_lookup", data: { "a_records" => ["1.2.3.4"] }),
      run_for("hosting_diagnostic", data: { "open_ports" => ["http", "https"] }),
      run_for("website_inspect", data: {
        "health" => "up", "status_code" => 200, "is_wordpress" => true, "wp_version" => "6.4",
        "critical_error" => false, "maintenance_mode" => false,
        "redirects_to_https" => true, "missing_headers" => [],
        "https_response" => { "status_code" => 200, "success" => true }
      }),
      run_for("ssl_inspect", data: { "certificate" => { "days_until_expiry" => 90 }, "deprecated_protocols" => [] })
    ]
  end

  def runs_with(key, **overrides)
    healthy_runs.map { |r| r.tool_key == key ? run_for(key, **overrides) : r }
  end

  def codes(result) = result.findings.map { |f| f["code"] }

  test "fully healthy -> healthy verdict + single externally-healthy finding, no suggested track" do
    res = Investigations::HostingWebsiteCorrelator.new(healthy_runs).call
    assert_equal "healthy", res.verdict_status
    assert_equal ["site_externally_healthy"], codes(res)
    assert_nil res.suggested_track
  end

  test "no resolution -> critical no_resolution" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("dns_lookup", data: { "a_records" => [] })).call
    assert_equal "critical", res.verdict_status
    assert_includes codes(res), "no_resolution"
  end

  test "site unreachable -> critical site_unreachable" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("website_inspect", data: {
      "health" => "unreachable",
      "redirects_to_https" => true, "missing_headers" => [],
      "https_response" => { "status_code" => 200, "success" => true }
    }, success: false)).call
    assert_includes codes(res), "site_unreachable"
    assert_equal "critical", res.verdict_status
  end

  test "server error -> critical site_server_error" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("website_inspect", data: {
      "health" => "server_error", "status_code" => 500,
      "redirects_to_https" => true, "missing_headers" => [],
      "https_response" => { "status_code" => 200, "success" => true }
    })).call
    assert_includes codes(res), "site_server_error"
    assert_equal "critical", res.verdict_status
  end

  test "WordPress critical error -> critical wp_critical_error with version in message" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("website_inspect", data: {
      "health" => "server_error", "status_code" => 500,
      "critical_error" => true, "is_wordpress" => true, "wp_version" => "6.4",
      "redirects_to_https" => true, "missing_headers" => [],
      "https_response" => { "status_code" => 200, "success" => true }
    })).call
    f = res.findings.find { |x| x["code"] == "wp_critical_error" }
    assert f
    assert_equal "critical", f["severity"]
    assert_match(/6\.4/, f["message"])
  end

  test "resolves but no web ports -> critical resolves_not_serving" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("hosting_diagnostic", data: { "open_ports" => ["ssh"] })).call
    assert_includes codes(res), "resolves_not_serving"
  end

  test "expired cert -> critical ssl_expired" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("ssl_inspect", data: { "certificate" => { "days_until_expiry" => -3 }, "deprecated_protocols" => [] })).call
    assert_includes codes(res), "ssl_expired"
    assert_equal "critical", res.verdict_status
  end

  test "cert expiring soon -> warning ssl_expiring" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("ssl_inspect", data: { "certificate" => { "days_until_expiry" => 7 }, "deprecated_protocols" => [] })).call
    assert_includes codes(res), "ssl_expiring"
    assert_equal "issues", res.verdict_status
  end

  test "maintenance mode -> warning maintenance_mode" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("website_inspect", data: {
      "health" => "server_error", "status_code" => 503, "maintenance_mode" => true,
      "redirects_to_https" => true, "missing_headers" => [],
      "https_response" => { "status_code" => 200, "success" => true }
    })).call
    assert_includes codes(res), "maintenance_mode"
  end

  test "homepage 4xx -> warning site_client_error" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("website_inspect", data: {
      "health" => "client_error", "status_code" => 403,
      "redirects_to_https" => true, "missing_headers" => [],
      "https_response" => { "status_code" => 200, "success" => true }
    })).call
    assert_includes codes(res), "site_client_error"
  end

  test "no HTTPS redirect -> warning no_https_redirect" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("website_inspect", data: {
      "health" => "up", "redirects_to_https" => false, "missing_headers" => [],
      "http_response" => { "success" => true }
    })).call
    assert_includes codes(res), "no_https_redirect"
  end

  test "deprecated TLS -> warning deprecated_tls" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("ssl_inspect", data: { "certificate" => { "days_until_expiry" => 90 }, "deprecated_protocols" => ["TLSv1.0"] })).call
    assert_includes codes(res), "deprecated_tls"
  end

  test "exposed DB port -> warning database_port_exposed" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("hosting_diagnostic", data: { "open_ports" => ["http", "https", "mysql"] })).call
    assert_includes codes(res), "database_port_exposed"
  end

  test "missing security headers -> info missing_security_headers, verdict stays healthy" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("website_inspect", data: {
      "health" => "up", "redirects_to_https" => true,
      "missing_headers" => ["Strict-Transport-Security"],
      "https_response" => { "status_code" => 200, "success" => true }
    })).call
    f = res.findings.find { |x| x["code"] == "missing_security_headers" }
    assert f
    assert_equal "info", f["severity"]
    # An info-only finding does NOT escalate the verdict — verdict_for only lifts on warning/critical.
    assert_equal "healthy", res.verdict_status
  end

  test "findings carry provenance" do
    res = Investigations::HostingWebsiteCorrelator.new(runs_with("dns_lookup", data: { "a_records" => [] })).call
    f = res.findings.find { |x| x["code"] == "no_resolution" }
    assert_equal ["dns_lookup"], f["provenance"]
  end
end
