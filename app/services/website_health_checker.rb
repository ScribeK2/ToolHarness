require "net/http"
require "uri"
require "json"
require "openssl"

# Fetches a site's homepage (HTTPS, HTTP fallback), classifies HTTP health, and
# detects WordPress + its critical-error/maintenance states. Pure Net::HTTP; never
# raises. The single HTTP seam #http_get is stubbed in tests (no live network).
class WebsiteHealthChecker
  OPEN_TIMEOUT   = 3
  READ_TIMEOUT   = 8
  MAX_REDIRECTS  = 5
  MAX_BODY_BYTES = 512 * 1024
  CRITICAL_ERROR_STRINGS = [
    "There has been a critical error on this website",
    "There has been a critical error on your website"
  ].freeze
  MAINTENANCE_STRING = "Briefly unavailable for scheduled maintenance".freeze

  def self.check(domain) = new(domain).check

  def initialize(domain)
    @domain = domain.to_s.strip
  end

  def check
    return unreachable_result("blank domain") if @domain.empty?

    resp = fetch_homepage
    return unreachable_result(resp[:error]) if resp[:status].to_i.zero?

    body       = resp[:body].to_s
    wp_json    = http_get("https://#{@domain}/wp-json/")
    wp_json_ok = (200..299).cover?(wp_json[:status].to_i)
    status     = resp[:status].to_i
    is_wp, evidence, version = detect_wordpress(body, wp_json_ok)

    data = {
      final_url:          resp[:final_url],
      fetched_over:       (URI.parse(resp[:final_url].to_s).scheme rescue "http"),
      status_code:        status,
      health:             classify(status),
      title:              extract_title(body),
      is_wordpress:       is_wp,
      wordpress_evidence: evidence,
      wp_version:         version,
      wp_json_available:  wp_json_ok,
      critical_error:     CRITICAL_ERROR_STRINGS.any? { |s| body.include?(s) },
      maintenance_mode:   body.include?(MAINTENANCE_STRING)
    }
    { success: true, **data, issues: build_issues(data) }
  end

  private

  def fetch_homepage
    https = http_get("https://#{@domain}/")
    return https unless https[:status].to_i.zero?
    http_get("http://#{@domain}/")
  end

  # Single HTTP seam — stubbed in tests. Returns { status:, body:, headers:, final_url: }.
  def http_get(url, redirects = 0)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.verify_mode  = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
    resp = http.get(uri.request_uri.presence || "/")

    if resp.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS && resp["location"].present?
      return http_get(absolute(resp["location"], uri), redirects + 1)
    end

    { status: resp.code.to_i, body: resp.body.to_s.byteslice(0, MAX_BODY_BYTES),
      headers: resp.to_hash, final_url: url }
  rescue StandardError => e
    { status: 0, body: nil, headers: {}, final_url: url, error: e.message }
  end

  def absolute(location, base)
    URI.join("#{base.scheme}://#{base.host}", location).to_s
  rescue StandardError
    location
  end

  def classify(status)
    case status
    when 200..299 then "up"
    when 300..399 then "down"
    when 400..499 then "client_error"
    when 500..599 then "server_error"
    else               "unreachable"
    end
  end

  def detect_wordpress(body, wp_json_ok)
    evidence = []
    version  = nil
    if (m = body.match(/<meta[^>]+name=["']generator["'][^>]+content=["']WordPress\s*([0-9.]+)?["']/i))
      evidence << "meta_generator"
      version = m[1].presence
    end
    evidence << "wp_paths" if body.include?("/wp-content/") || body.include?("/wp-includes/")
    evidence << "wp_json"  if wp_json_ok
    [evidence.any?, evidence, version]
  end

  def extract_title(body)
    body[/<title[^>]*>(.*?)<\/title>/im, 1]&.strip
  end

  def build_issues(data)
    issues = []
    case data[:health]
    when "server_error", "down"
      issues << issue("critical", "site_server_error", "Server error",
                      "The homepage responded with HTTP #{data[:status_code]}.",
                      "Check the web server and application/PHP error logs.")
    when "client_error"
      issues << issue("warning", "site_client_error", "Client error",
                      "The homepage responded with HTTP #{data[:status_code]}.",
                      "Check access rules / document root / index file.")
    end
    if data[:critical_error]
      issues << issue("critical", "wp_critical_error", "WordPress critical error",
                      "WordPress is showing its critical-error page.",
                      "Check wp-content/debug.log and recently changed plugins/themes.")
    end
    if data[:maintenance_mode]
      issues << issue("warning", "maintenance_mode", "Maintenance mode",
                      "WordPress is showing the scheduled-maintenance page.",
                      "Remove the .maintenance file from the WordPress root.")
    end
    if data[:is_wordpress]
      issues << issue("info", "wordpress_detected", "WordPress detected",
                      "WordPress#{data[:wp_version] ? " #{data[:wp_version]}" : ''} detected via #{data[:wordpress_evidence].join(', ')}.",
                      "—")
    end
    issues
  end

  def issue(severity, code, title, message, recommendation)
    { "severity" => severity, "code" => code, "title" => title,
      "message" => message, "recommendation" => recommendation }
  end

  def unreachable_result(err)
    {
      success: false, final_url: nil, fetched_over: nil, status_code: nil,
      health: "unreachable", title: nil, is_wordpress: false, wordpress_evidence: [],
      wp_version: nil, wp_json_available: false, critical_error: false,
      maintenance_mode: false, error: err,
      issues: [issue("critical", "site_unreachable", "Site unreachable",
                     "No response over HTTPS or HTTP.",
                     "Confirm the web server/container is running and listening.")]
    }
  end
end
