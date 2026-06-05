require "net/http"
require "uri"
require "json"

# Pure-Net::HTTP IPinfo client. Credential-agnostic — the caller injects the token.
# Never raises. The HTTP seam #http_get_json is stubbed in tests (no live network).
class IpinfoChecker
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 8

  def self.check(ip, token:) = new(ip, token: token).check

  def initialize(ip, token:)
    @ip    = ip.to_s
    @token = token.to_s
  end

  def check
    resp   = http_get_json("https://ipinfo.io/#{@ip}?token=#{@token}")
    status = resp[:status].to_i
    return error_result(status_error(status, resp[:error])) unless status == 200 && resp[:body].is_a?(Hash)

    map(resp[:body])
  end

  private

  def map(b)
    asn = parse_asn(b)
    {
      success:  true,
      ip:       b["ip"],
      hostname: b["hostname"],
      city:     b["city"],
      region:   b["region"],
      country:  b["country"],
      loc:      b["loc"],
      postal:   b["postal"],
      timezone: b["timezone"],
      asn:      asn,
      org:      (b["org"] if asn.nil? && b["org"].present?),
      company:  company(b["company"]),
      privacy:  privacy(b["privacy"]),
      error:    nil
    }
  end

  def parse_asn(b)
    if b["asn"].is_a?(Hash) && b["asn"]["asn"].present?
      { id: b["asn"]["asn"], name: b["asn"]["name"] }
    elsif (m = b["org"].to_s.match(/\A(AS\d+)\s+(.*)/))
      { id: m[1], name: m[2] }
    end
  end

  def company(c)
    return nil unless c.is_a?(Hash)
    { name: c["name"], domain: c["domain"], type: c["type"] }
  end

  def privacy(p)
    return nil unless p.is_a?(Hash)
    { vpn: p["vpn"], proxy: p["proxy"], tor: p["tor"], relay: p["relay"], hosting: p["hosting"] }
  end

  def status_error(status, neterr)
    case status
    when 401, 403 then "IPinfo rejected the API key (HTTP #{status})"
    when 429      then "IPinfo rate limit reached (HTTP 429)"
    when 0        then "IPinfo request failed: #{neterr || 'network error'}"
    else               "IPinfo returned HTTP #{status}"
    end
  end

  def error_result(msg)
    { success: false, error: msg, ip: @ip, hostname: nil, city: nil, region: nil,
      country: nil, loc: nil, postal: nil, timezone: nil, asn: nil, org: nil,
      company: nil, privacy: nil }
  end

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
