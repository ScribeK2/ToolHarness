require "net/http"
require "uri"
require "json"

# Pure-Net::HTTP PageSpeed Insights client. Credential-agnostic — the caller injects
# the optional API key. Never raises. The HTTP seam #http_get_json is stubbed in tests.
class PagespeedChecker
  ENDPOINT     = "https://www.googleapis.com/pagespeedonline/v5/runPagespeed".freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 50 # PSI runs a real Lighthouse pass; 15-40s is normal.

  def self.check(url, strategy:, key: nil) = new(url, strategy: strategy, key: key).check

  def initialize(url, strategy:, key: nil)
    @url      = url.to_s
    @strategy = %w[mobile desktop].include?(strategy.to_s) ? strategy.to_s : "mobile"
    @key      = key.to_s
  end

  def check
    resp   = http_get_json(request_url)
    status = resp[:status].to_i
    body   = resp[:body]

    if status == 200 && body.is_a?(Hash) && body["lighthouseResult"].is_a?(Hash)
      runtime_error = body.dig("lighthouseResult", "runtimeError", "message")
      return failure(runtime_error) if runtime_error.present?
      return { success: true, body: body }
    end

    failure(status_error(status, body, resp[:error]))
  end

  private

  def request_url
    params = { url: @url, strategy: @strategy, category: "performance" }
    params[:key] = @key if @key.present?
    "#{ENDPOINT}?#{URI.encode_www_form(params)}"
  end

  def status_error(status, body, neterr)
    api_msg = body.is_a?(Hash) ? body.dig("error", "message") : nil
    case status
    when 429 then "PageSpeed quota exceeded (HTTP 429) — add a Google API key in the Credentials tool (id: pagespeed) to raise the limit."
    when 0   then "PageSpeed request failed: #{neterr || 'network error'}"
    else          api_msg.presence || "PageSpeed returned HTTP #{status}"
    end
  end

  def failure(msg) = { success: false, error: msg.to_s, body: nil }

  # HTTP seam — stubbed in tests. Returns { status: Integer, body: Hash|nil }.
  def http_get_json(url)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    resp = http.get(uri.request_uri, "Accept" => "application/json")
    body = (JSON.parse(resp.body) rescue nil)
    { status: resp.code.to_i, body: body }
  rescue StandardError => e
    { status: 0, body: nil, error: e.message }
  end
end
