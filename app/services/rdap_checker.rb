require "net/http"
require "json"
require "time"
require "ipaddr"

# RDAP lookup for a domain or IP. Mirrors WhoisChecker.check's normalized hash
# shape so callers/views are source-agnostic. Discovery: IANA bootstrap (via
# Rdap::Bootstrap) then the rdap.org redirector. Never raises; failures land in
# :issues and :success=false so the tool can fall back to WHOIS.
class RdapChecker
  RDAP_ORG = "https://rdap.org".freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  MAX_REDIRECTS = 5

  def self.check(query) = new(query).check

  def initialize(query, bootstrap: Rdap::Bootstrap.new)
    @query     = query.to_s.strip
    @bootstrap = bootstrap
    @record_type = ip?(@query) ? :ip : :domain
  end

  def check
    base = @bootstrap.base_for(@query, @record_type)
    if base
      resp = http_get_json(object_url(base))
      return parse(resp[:body], source: :rdap_registry) if ok?(resp)
      return not_found_result if resp && resp[:status] == 404
    end
    resp = http_get_json("#{RDAP_ORG}/#{path_segment}/#{@query}")
    return parse(resp[:body], source: :rdap_bootstrap_redirect) if ok?(resp)
    return not_found_result if resp && resp[:status] == 404

    failure("RDAP lookup failed (no endpoint or server error).")
  end

  private

  def ip?(s)
    IPAddr.new(s); true
  rescue IPAddr::Error
    false
  end

  def path_segment = (@record_type == :ip ? "ip" : "domain")
  def object_url(base) = "#{base.chomp('/')}/#{path_segment}/#{@query}"
  def ok?(resp) = resp && resp[:status].to_i.between?(200, 299) && resp[:body].is_a?(Hash)

  # Single HTTP seam — stub in tests. Returns { status: Integer, body: Hash|nil }.
  # Follows up to MAX_REDIRECTS 3xx hops (rdap.org issues a 302).
  def http_get_json(url, redirects = 0)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    resp = http.get(uri.request_uri, "Accept" => "application/rdap+json, application/json")

    if resp.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS
      return http_get_json(resp["location"], redirects + 1)
    end

    body = (JSON.parse(resp.body) rescue nil)
    { status: resp.code.to_i, body: body }
  rescue StandardError => e
    { status: 0, body: nil, error: e.message }
  end

  def base_result
    {
      success: false, record_type: @record_type, source: nil,
      query: @query, raw_data: nil, error: nil, issues: []
    }
  end

  def failure(msg)
    base_result.merge(success: false, error: msg)
  end

  def not_found_result
    base_result.merge(
      success: true, source: :rdap_registry,
      issues: [{ severity: "info", code: "rdap_not_found",
                 title: "Not registered", message: "RDAP reports no record for #{@query}.",
                 recommendation: "The object may be unregistered or available." }]
    )
  end

  def parse(body, source:)
    @record_type == :ip ? parse_ip(body, source) : parse_domain(body, source)
  end

  def parse_domain(d, source)
    events = Array(d["events"])
    base_result.merge(
      success: true, source: source,
      raw_data: JSON.pretty_generate(d),
      registrar: registrar_name(d),
      expiration_date: event_date(events, "expiration"),
      creation_date:   event_date(events, "registration"),
      updated_date:    event_date(events, "last changed"),
      nameservers: Array(d["nameservers"]).map { |n| n["ldhName"].to_s.downcase }.reject(&:blank?),
      registrant: entity_name(d, "registrant"),
      statuses: Array(d["status"]),
      entities: parse_entities(d["entities"])
    )
  end

  def parse_ip(d, source)
    start_a = d["startAddress"]
    end_a   = d["endAddress"]
    abuse   = Array(d["entities"]).find { |e| Array(e["roles"]).include?("abuse") }
    base_result.merge(
      success: true, source: source,
      raw_data: JSON.pretty_generate(d),
      ip_range: ([start_a, end_a].all?(&:present?) ? "#{start_a} – #{end_a}" : nil),
      cidr: cidr_from(start_a, end_a),
      network_name: d["name"],
      network_type: d["type"],
      rir: rir_from(d),
      country: d["country"],
      organization: entity_name(d, "registrant"),
      abuse_contact: (abuse && vcard_value(abuse, "email")),
      entities: parse_entities(d["entities"]),
      events: Array(d["events"]).map { |e| { action: e["eventAction"], date: e["eventDate"] } }
    )
  end

  def cidr_from(start_a, end_a)
    return nil unless start_a.present? && end_a.present?
    lo = IPAddr.new(start_a); hi = IPAddr.new(end_a)
    range = (hi.to_i - lo.to_i + 1)
    bits = lo.ipv6? ? 128 : 32
    prefix = bits - Math.log2(range).to_i
    "#{start_a}/#{prefix}"
  rescue StandardError
    nil
  end

  # Best-effort RIR from the port43 whois host or rdap base.
  def rir_from(d)
    host = d["port43"].to_s
    return "ARIN"    if host.include?("arin")
    return "RIPE"    if host.include?("ripe")
    return "APNIC"   if host.include?("apnic")
    return "LACNIC"  if host.include?("lacnic")
    return "AFRINIC" if host.include?("afrinic")
    nil
  end

  def event_date(events, action)
    ev = events.find { |e| e["eventAction"].to_s.casecmp?(action) }
    return nil unless ev && ev["eventDate"]
    Time.parse(ev["eventDate"]).iso8601 rescue ev["eventDate"]
  end

  def registrar_name(d)
    reg = Array(d["entities"]).find { |e| Array(e["roles"]).include?("registrar") }
    reg && vcard_value(reg, "fn")
  end

  def entity_name(d, role)
    e = Array(d["entities"]).find { |ent| Array(ent["roles"]).include?(role) }
    e && (vcard_value(e, "fn") || vcard_value(e, "org"))
  end

  def parse_entities(entities)
    Array(entities).map do |e|
      {
        roles: Array(e["roles"]),
        name: vcard_value(e, "fn"),
        organization: vcard_value(e, "org"),
        email: vcard_value(e, "email"),
        phone: vcard_value(e, "tel")
      }
    end
  end

  # vcardArray = ["vcard", [ [name, params, type, value], ... ]]
  def vcard_value(entity, field)
    vcard = entity["vcardArray"]
    return nil unless vcard.is_a?(Array) && vcard[1].is_a?(Array)
    row = vcard[1].find { |r| r.is_a?(Array) && r[0].to_s.casecmp?(field) }
    val = row && row[3]
    val.is_a?(Array) ? val.join(" ").strip : val
  end
end
