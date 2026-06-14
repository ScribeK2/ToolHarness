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
      origin_ip: origin_ip(timeline)
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

  def public_ip?(ip)
    addr = IPAddr.new(ip)
    return false if addr.loopback? || addr.link_local?
    return false if addr.ipv4? && (addr.private? || addr.to_s.start_with?("169.254"))
    !(addr.ipv4? && addr.private?)
  rescue IPAddr::Error
    false
  end
end
