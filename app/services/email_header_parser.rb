class EmailHeaderParser
  MULTI_HEADERS = %w[received].freeze

  def initialize(raw)
    @raw = raw.to_s
  end

  def analyze
    headers = parse_headers(header_block(normalize(@raw)))
    return { ok: false, headers: {} } if headers.empty?

    { ok: true, headers: headers }
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
end
