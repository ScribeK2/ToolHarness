require "net/http"
require "uri"
require "openssl"

# Single-pass website inspection: fetches the homepage over HTTPS (HTTP
# fallback) capturing the body, probes plain HTTP for the HTTPS redirect,
# checks /wp-json/, classifies HTTP health, detects WordPress and its
# critical-error/maintenance states, and evaluates security headers.
# Merged engine behind Tools::WebsiteInspect (replaces WebsiteHealthChecker
# and HttpChecker). Never raises. The single HTTP seam #http_get is stubbed
# in tests (no live network).
class WebsiteInspector
  OPEN_TIMEOUT   = 3
  READ_TIMEOUT   = 8
  MAX_REDIRECTS  = 5
  MAX_BODY_BYTES = 512 * 1024
  SLOW_MS        = 3000
  CRITICAL_ERROR_STRINGS = [
    "There has been a critical error on this website",
    "There has been a critical error on your website"
  ].freeze
  MAINTENANCE_STRING = "Briefly unavailable for scheduled maintenance".freeze

  # Header keys as sent; lookups use the lowercased form (Net::HTTP#to_hash).
  SECURITY_HEADERS = {
    "Strict-Transport-Security" => { name: "HSTS",                   required: true,  severity: "warning" },
    "Content-Security-Policy"   => { name: "CSP",                    required: false, severity: "info" },
    "X-Frame-Options"           => { name: "X-Frame-Options",        required: true,  severity: "warning" },
    "X-Content-Type-Options"    => { name: "X-Content-Type-Options", required: true,  severity: "warning" },
    "Referrer-Policy"           => { name: "Referrer-Policy",        required: false, severity: "info" },
    "Permissions-Policy"        => { name: "Permissions-Policy",     required: false, severity: "info" }
  }.freeze

  def self.check(domain) = new(domain).check

  def initialize(domain)
    @domain = domain.to_s.strip
  end

  def check
    return unreachable_result("blank domain") if @domain.empty?

    https   = http_get("https://#{@domain}/")
    http    = http_get("http://#{@domain}/")
    primary = https[:status].to_i.positive? ? https : http
    return unreachable_result(primary[:error]) if primary[:status].to_i.zero?

    body       = primary[:body].to_s
    wp_json    = http_get("https://#{@domain}/wp-json/")
    wp_json_ok = (200..299).cover?(wp_json[:status].to_i)
    status     = primary[:status].to_i
    headers    = primary[:headers] || {}
    is_wp, evidence, version = detect_wordpress(body, wp_json_ok)

    data = {
      domain:             @domain,
      final_url:          primary[:final_url],
      fetched_over:       (URI.parse(primary[:final_url].to_s).scheme rescue "http"),
      status_code:        status,
      response_time_ms:   primary[:response_time_ms],
      health:             classify(status),
      title:              extract_title(body),
      https_response:     response_summary(https),
      http_response:      response_summary(http),
      redirects_to_https: http[:status].to_i.positive? && http[:final_url].to_s.start_with?("https://"),
      security_headers:   analyze_security_headers(headers),
      missing_headers:    find_missing_headers(headers),
      server_info:        { server: header(headers, "server"), powered_by: header(headers, "x-powered-by") },
      is_wordpress:       is_wp,
      wordpress_evidence: evidence,
      wp_version:         version,
      wp_json_available:  wp_json_ok,
      critical_error:     CRITICAL_ERROR_STRINGS.any? { |s| body.include?(s) },
      maintenance_mode:   body.include?(MAINTENANCE_STRING)
    }
    { success: true, **data, issues: health_issues(data) + web_issues(data) }
  end

  private

  # Single HTTP seam — stubbed in tests. Follows redirects; returns
  # { status:, body:, headers:, final_url:, response_time_ms:, error: }.
  def http_get(url, redirects = 0)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.verify_mode  = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    resp    = http.get(uri.request_uri.presence || "/")
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    if resp.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS && resp["location"].present?
      return http_get(absolute(resp["location"], uri), redirects + 1)
    end

    { status: resp.code.to_i, body: resp.body.to_s.byteslice(0, MAX_BODY_BYTES),
      headers: resp.to_hash, final_url: url, response_time_ms: elapsed }
  rescue StandardError => e
    { status: 0, body: nil, headers: {}, final_url: url, response_time_ms: nil, error: e.message }
  end

  def absolute(location, base)
    URI.join("#{base.scheme}://#{base.host}", location).to_s
  rescue StandardError
    location
  end

  def response_summary(resp)
    { success: resp[:status].to_i.positive?,
      status_code: resp[:status].to_i.nonzero?,
      final_url: resp[:final_url],
      response_time_ms: resp[:response_time_ms],
      error: resp[:error] }.compact
  end

  def header(headers, lower_key) = Array(headers[lower_key]).first

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

  def analyze_security_headers(headers)
    SECURITY_HEADERS.each_with_object({}) do |(header_name, config), analysis|
      value = header(headers, header_name.downcase)
      analysis[header_name] = {
        present: value.present?,
        value: value,
        name: config[:name]
      }
    end
  end

  # Names (strings) of required headers that are absent.
  def find_missing_headers(headers)
    SECURITY_HEADERS.select { |name, config| config[:required] && header(headers, name.downcase).blank? }
                    .keys
  end

  def health_issues(data)
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

  def web_issues(data)
    issues = []
    unless data.dig(:https_response, :success)
      issues << issue("critical", "no_https", "HTTPS not available",
                      "The site is not accessible over HTTPS.",
                      "Install an SSL certificate and enable HTTPS.")
      return issues
    end
    if data.dig(:http_response, :success) && !data[:redirects_to_https]
      issues << issue("warning", "no_https_redirect", "No HTTPS redirect",
                      "HTTP requests are not redirected to HTTPS.",
                      "Configure HTTP to redirect to HTTPS for all requests.")
    end
    data[:missing_headers].each do |name|
      config = SECURITY_HEADERS[name]
      issues << issue(config[:severity], "missing_#{name.downcase.tr('-', '_')}",
                      "Missing #{config[:name]}",
                      "#{name} header is not set.",
                      "Add the #{name} header to improve security.")
    end
    if data[:server_info][:powered_by].present?
      issues << issue("info", "powered_by_disclosed", "Technology stack disclosed",
                      "X-Powered-By header reveals: #{data[:server_info][:powered_by]}",
                      "Consider removing the X-Powered-By header.")
    end
    if data[:response_time_ms] && data[:response_time_ms] > SLOW_MS
      issues << issue("warning", "slow_response", "Slow response time",
                      "Server response time is #{data[:response_time_ms]}ms.",
                      "Investigate server performance issues.")
    end
    issues
  end

  def issue(severity, code, title, message, recommendation)
    { "severity" => severity, "code" => code, "title" => title,
      "message" => message, "recommendation" => recommendation }
  end

  def unreachable_result(err)
    {
      success: false, domain: @domain, final_url: nil, fetched_over: nil,
      status_code: nil, response_time_ms: nil, health: "unreachable", title: nil,
      https_response: { success: false }, http_response: { success: false },
      redirects_to_https: false, security_headers: {}, missing_headers: [],
      server_info: {}, is_wordpress: false, wordpress_evidence: [],
      wp_version: nil, wp_json_available: false, critical_error: false,
      maintenance_mode: false, error: err,
      issues: [issue("critical", "site_unreachable", "Site unreachable",
                     "No response over HTTPS or HTTP.",
                     "Confirm the web server/container is running and listening.")]
    }
  end
end
