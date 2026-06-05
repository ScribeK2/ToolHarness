require "test_helper"

class WebsiteHealthCheckerTest < ActiveSupport::TestCase
  # Stub the single HTTP seam. The lambda branches on URL so the homepage and
  # the /wp-json/ probe can return different canned responses.
  def check_with(home:, wp_json: { status: 404, body: "", headers: {}, final_url: "x" })
    c = WebsiteHealthChecker.new("example.com")
    c.stub(:http_get, ->(url, *_) { url.include?("/wp-json") ? wp_json : home }) do
      c.check
    end
  end

  def ok(status:, body:, final_url: "https://example.com/")
    { status: status, body: body, headers: {}, final_url: final_url }
  end

  test "200 WordPress site -> up, wordpress detected with version" do
    body = '<html><head><meta name="generator" content="WordPress 6.4.2"><title>Acme</title></head><body>/wp-content/themes</body></html>'
    r = check_with(home: ok(status: 200, body: body), wp_json: ok(status: 200, body: "{}"))
    assert r[:success]
    assert_equal "up", r[:health]
    assert r[:is_wordpress]
    assert_includes r[:wordpress_evidence], "meta_generator"
    assert_includes r[:wordpress_evidence], "wp_json"
    assert_equal "6.4.2", r[:wp_version]
    assert_equal "Acme", r[:title]
    refute r[:critical_error]
  end

  test "WordPress critical error page -> critical_error true, health server_error" do
    body = "<html><body>There has been a critical error on this website.</body></html>"
    r = check_with(home: ok(status: 500, body: body))
    assert_equal "server_error", r[:health]
    assert r[:critical_error]
    assert_includes r[:issues].map { |i| i["code"] }, "wp_critical_error"
  end

  test "maintenance page -> maintenance_mode true" do
    body = "<html><body>Briefly unavailable for scheduled maintenance. Check back in a minute.</body></html>"
    r = check_with(home: ok(status: 503, body: body))
    assert r[:maintenance_mode]
    assert_includes r[:issues].map { |i| i["code"] }, "maintenance_mode"
  end

  test "404 homepage -> client_error" do
    r = check_with(home: ok(status: 404, body: "nope"))
    assert_equal "client_error", r[:health]
    assert_includes r[:issues].map { |i| i["code"] }, "site_client_error"
  end

  test "non-WordPress 200 site -> up, not wordpress" do
    r = check_with(home: ok(status: 200, body: "<html><body>plain</body></html>"))
    assert_equal "up", r[:health]
    refute r[:is_wordpress]
    assert_empty r[:wordpress_evidence]
  end

  test "unreachable (status 0) -> failed, unreachable, site_unreachable issue" do
    r = check_with(home: { status: 0, body: nil, headers: {}, final_url: "https://example.com/", error: "timeout" })
    refute r[:success]
    assert_equal "unreachable", r[:health]
    assert_includes r[:issues].map { |i| i["code"] }, "site_unreachable"
  end
end
