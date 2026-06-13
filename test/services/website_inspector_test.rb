require "test_helper"

class WebsiteInspectorTest < ActiveSupport::TestCase
  # Stub the single HTTP seam; the lambda branches on URL so the HTTPS homepage,
  # plain-HTTP probe, and /wp-json/ probe return different canned responses.
  def check_with(https:, http: nil, wp_json: nil)
    http    ||= { status: 301, body: "", headers: {}, final_url: "https://example.com/", response_time_ms: 40 }
    wp_json ||= { status: 404, body: "", headers: {}, final_url: "x", response_time_ms: 10 }
    c = WebsiteInspector.new("example.com")
    c.stub(:http_get, lambda { |url, *_|
      if url.include?("/wp-json")        then wp_json
      elsif url.start_with?("http://")   then http
      else https
      end
    }) { c.check }
  end

  def ok(status:, body:, headers: {}, final_url: "https://example.com/", time: 120)
    { status: status, body: body, headers: headers, final_url: final_url, response_time_ms: time }
  end

  test "healthy WordPress site over HTTPS" do
    body = '<html><head><meta name="generator" content="WordPress 6.4.2"><title>Acme</title></head><body>/wp-content/x</body></html>'
    headers = { "strict-transport-security" => ["max-age=63072000"], "server" => ["nginx"] }
    r = check_with(https: ok(status: 200, body: body, headers: headers),
                   wp_json: ok(status: 200, body: "{}"))
    assert r[:success]
    assert_equal "up", r[:health]
    assert_equal "https", r[:fetched_over]
    assert_equal "Acme", r[:title]
    assert r[:is_wordpress]
    assert_equal "6.4.2", r[:wp_version]
    assert r[:redirects_to_https]
    assert_equal "nginx", r[:server_info][:server]
    refute_includes r[:missing_headers], "Strict-Transport-Security"
    assert_includes r[:missing_headers], "X-Frame-Options"
  end

  test "wp critical error page" do
    body = "<html><body>There has been a critical error on this website.</body></html>"
    r = check_with(https: ok(status: 500, body: body))
    assert_equal "server_error", r[:health]
    assert r[:critical_error]
    assert_includes r[:issues].map { |i| i["code"] }, "wp_critical_error"
  end

  test "maintenance page" do
    body = "<html><body>Briefly unavailable for scheduled maintenance.</body></html>"
    r = check_with(https: ok(status: 503, body: body))
    assert r[:maintenance_mode]
    assert_includes r[:issues].map { |i| i["code"] }, "maintenance_mode"
  end

  test "falls back to plain HTTP when HTTPS fails, flags no_https" do
    dead = { status: 0, body: nil, headers: {}, final_url: "https://example.com/", error: "refused" }
    live = ok(status: 200, body: "<html><title>Plain</title></html>", final_url: "http://example.com/")
    r = check_with(https: dead, http: live)
    assert r[:success]
    assert_equal "http", r[:fetched_over]
    refute r[:redirects_to_https]
    assert_includes r[:issues].map { |i| i["code"] }, "no_https"
  end

  test "no http→https redirect is flagged" do
    plain = ok(status: 200, body: "x", final_url: "http://example.com/")
    r = check_with(https: ok(status: 200, body: "<html></html>"), http: plain)
    refute r[:redirects_to_https]
    assert_includes r[:issues].map { |i| i["code"] }, "no_https_redirect"
  end

  test "completely unreachable" do
    dead = { status: 0, body: nil, headers: {}, final_url: "x", error: "timeout" }
    r = check_with(https: dead, http: dead)
    refute r[:success]
    assert_equal "unreachable", r[:health]
    assert_includes r[:issues].map { |i| i["code"] }, "site_unreachable"
  end

  test "blank domain" do
    r = WebsiteInspector.check("")
    refute r[:success]
    assert_equal "unreachable", r[:health]
  end
end
