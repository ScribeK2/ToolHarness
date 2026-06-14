require "time"
require "ipaddr"

class EmailHeaderParser
  MULTI_HEADERS = %w[received].freeze

  def initialize(raw)
    @raw = raw.to_s
  end

  def analyze
    headers = parse_headers(header_block(normalize(@raw)))
    return { ok: false, headers: {} } if headers.empty?

    timeline = build_timeline(headers["received"] || [])
    {
      ok: true,
      headers: headers,
      timeline: timeline,
      origin_ip: origin_ip(timeline),
      auth: parse_auth(headers["authentication-results"]),
      alignment: build_alignment(headers, timeline)
    }
  end

  private

  # Strip forwarding quote markers (">", "> "), normalize CRLF -> LF.
  def normalize(text)
    text.gsub("\r\n", "\n").lines.map { |l| l.sub(/\A>\s?/, "") }.join
  end

  # Everything up to the first blank line is the header block.
  def header_block(text)
    text.split(/\n[ \t]*\n/, 2).first.to_s
  end

  # Unfold continuation lines (leading whitespace) and split into name => value.
  # Repeated MULTI_HEADERS accumulate into arrays; others keep the last value.
  def parse_headers(block)
    headers = {}
    current_name = nil
    block.each_line do |line|
      line = line.chomp
      if line =~ /\A[ \t]+(.*)\z/ && current_name # folded continuation
        append(headers, current_name, " #{$1.strip}", fold: true)
      elsif line =~ /\A([A-Za-z0-9\-]+):[ \t]?(.*)\z/
        current_name = $1.downcase
        append(headers, current_name, $2)
      end
    end
    headers
  end

  def append(headers, name, value, fold: false)
    if MULTI_HEADERS.include?(name)
      headers[name] ||= []
      if fold
        headers[name][-1] = "#{headers[name][-1]}#{value}"
      else
        headers[name] << value
      end
    else
      headers[name] = fold ? "#{headers[name]}#{value}" : value
    end
    headers
  end

  # Received headers stack newest-first; reverse to chronological order.
  def build_timeline(received_raw)
    hops = received_raw.reverse.each_with_index.map { |raw, i| parse_received(raw, i) }
    prev = nil
    hops.each do |hop|
      if hop[:time] && prev
        hop[:delay_s] = (Time.iso8601(hop[:time]) - Time.iso8601(prev)).to_f
      end
      prev = hop[:time] || prev
    end
    times = hops.filter_map { |h| h[:time] }
    total = (times.size >= 2) ? (Time.iso8601(times.last) - Time.iso8601(times.first)).to_f : nil
    { hops: hops, total_transit_s: total, originating_index: originating_index(hops) }
  end

  def parse_received(raw, index)
    ts = raw.split(";").last.to_s.strip
    time = parse_time(ts)
    {
      index: index,
      from_host: raw[/from\s+([^\s(]+)/i, 1],
      from_ip:   raw[/[\[(]\s*((?:\d{1,3}\.){3}\d{1,3})\s*[\])]/, 1] || raw[/\bIPv6:([0-9a-fA-F:]+)/, 1],
      by_host:   raw[/by\s+([^\s(]+)/i, 1],
      with:      raw[/with\s+([A-Za-z0-9]+)/i, 1],
      id:        raw[/\bid\s+(\S+)/i, 1],
      for:       raw[/for\s+<?([^>\s;]+)>?/i, 1],
      time:      time&.iso8601,
      delay_s:   nil
    }
  end

  def parse_time(str)
    return nil if str.to_s.empty?
    Time.parse(str.sub(/\s*\([^)]*\)\s*\z/, "")) # drop trailing "(PDT)" style comments
  rescue ArgumentError
    nil
  end

  def originating_index(hops)
    hops.index { |h| h[:from_ip] && public_ip?(h[:from_ip]) }
  end

  def origin_ip(timeline)
    idx = timeline[:originating_index]
    idx && timeline[:hops][idx][:from_ip]
  end

  def parse_auth(value)
    text = value.to_s
    %i[spf dkim dmarc compauth].index_with do |method|
      text[/\b#{method}=([a-zA-Z]+)/, 1]&.downcase
    end
  end

  # Public = not private (incl. IPv6 ULA fc00::/7), loopback, or link-local —
  # for both IPv4 and IPv6. IPAddr#private?/#loopback?/#link_local? cover both
  # families. Only public origins are pivoted through enrichment.
  def public_ip?(ip)
    addr = IPAddr.new(ip)
    !(addr.private? || addr.loopback? || addr.link_local?)
  rescue IPAddr::Error
    false
  end

  def build_alignment(headers, timeline)
    from_d  = domain_of(headers["from"])
    rp_d    = domain_of(headers["return-path"])
    mid_d   = domain_of(headers["message-id"])
    {
      from_domain: from_d,
      return_path_domain: rp_d,
      reply_to_domain: domain_of(headers["reply-to"]),
      message_id_domain: mid_d,
      from_return_path_aligned: aligned?(from_d, rp_d),
      message_id_aligned: aligned?(from_d, mid_d),
      date_skew_s: date_skew(headers["date"], timeline),
      spam_score: spam_score(headers)
    }
  end

  # Extract the domain from an address / message-id / "Name <a@b.com>" value.
  def domain_of(value)
    return nil if value.to_s.empty?
    value[/@([A-Za-z0-9.\-]+)/, 1]&.downcase&.sub(/[>\s)]+\z/, "")
  end

  # Aligned when equal or sharing the same organizational domain (last two
  # labels) — DMARC relaxed alignment. Reduces false spoofing flags on
  # legitimate ESP bounce-subdomains (e.g. mailer.ex.com vs ex.com).
  def aligned?(a, b)
    return false if a.nil? || b.nil?
    return true if a == b
    org(a) == org(b)
  end

  # NOTE: naive last-two-labels org domain; no Public Suffix List (AppImage has
  # no host deps), so multi-part ccTLDs like co.uk collapse to "co.uk". Acceptable
  # for a Tier-2 signal that is always weighed against the auth verdicts.
  def org(domain)
    domain.split(".").last(2).join(".")
  end

  def date_skew(date_value, timeline)
    return nil if date_value.to_s.empty?
    first = timeline[:hops].filter_map { |h| h[:time] }.first
    return nil unless first
    d = parse_time(date_value)
    d && (parse_time(first) - d).to_f.abs
  end

  def spam_score(headers)
    val = headers.find { |k, _| k.start_with?("x-spam-score") || k == "x-spam-status" }&.last
    val && val[/-?\d+(\.\d+)?/]&.to_f
  end
end
