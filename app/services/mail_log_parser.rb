require "time"

# Pure, network-free parser for pasted Postfix / Dovecot-LMTP delivery logs
# (as copied out of Graylog). Groups lines by Postfix queue id and reconstructs
# each message's delivery story + a verdict. Never raises on garbage input.
class MailLogParser
  # Postfix program tag: postfix/<daemon>[pid]:  (tolerates instance names like
  # postfix/submission/smtpd). Captures the daemon and the payload after it.
  PF_TAG = %r{postfix(?:/[\w.-]+)*/(smtpd|cleanup|qmgr|smtp|lmtp|bounce)\[\d+\]:\s*(.*)\z}
  DC_TAG = %r{\bdovecot:\s*(.*)\z}
  # "<qid>: rest" — Postfix queue ids are 6–16 alphanumerics.
  QID    = /\A([0-9A-Za-z]{6,}):\s*(.*)\z/

  def initialize(raw)
    @raw = raw.to_s
  end

  def analyze
    messages    = {}   # qid => record (insertion-ordered)
    rejections  = []
    unparsed    = 0

    logical_lines.each do |line|
      if (m = line.match(PF_TAG))
        handle_postfix(m[1], m[2], extract_time(line), messages, rejections)
      elsif line.match(DC_TAG)
        # Dovecot's own LMTP lines add no delivery fact beyond Postfix's lmtp
        # status line in v1; recognized (not counted as unparsed) but ignored.
        next
      else
        unparsed += 1
      end
    end

    msgs = messages.values
    msgs.each { |rec| rec[:verdict] = verdict_for(rec) }
    msgs = msgs.sort_by { |r| r[:time].to_s }

    if msgs.empty? && rejections.empty?
      return { ok: false, messages: [], rejections: [], unparsed_count: unparsed }
    end

    { ok: true, messages: msgs, rejections: rejections, unparsed_count: unparsed }
  end

  private

  # Graylog copies often hard-wrap long records across several physical lines.
  # A real record always carries a program tag (postfix/<daemon>[pid]: or
  # dovecot:); a wrapped continuation fragment never does — so fold any line
  # without a tag onto the previous logical line. Leading fragments with no
  # preceding record stand alone (and fall through to unparsed).
  def logical_lines
    lines = []
    @raw.gsub("\r\n", "\n").each_line do |raw|
      line = raw.chomp
      next if line.strip.empty?
      if record_start?(line) || lines.empty?
        lines << line
      else
        lines[-1] = "#{lines[-1]} #{line.strip}"
      end
    end
    lines
  end

  def record_start?(line)
    line.match?(PF_TAG) || line.match?(DC_TAG)
  end

  def extract_time(line)
    if (m = line.match(/\A(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)/))
      parse_time(m[1])
    elsif (m = line.match(/\b([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\b/))
      parse_time(m[1])
    end
  end

  def parse_time(str)
    Time.parse(str).iso8601
  rescue ArgumentError
    nil
  end

  def handle_postfix(daemon, payload, ts, messages, rejections)
    if daemon == "smtpd" && payload.start_with?("NOQUEUE: reject")
      rej = parse_rejection(payload, ts)
      rejections << rej if rej
      return
    end

    return unless (m = payload.match(QID))
    qid, rest = m[1], m[2]
    rec = (messages[qid] ||= new_record(qid, ts))

    case daemon
    when "smtpd"
      if (c = rest.match(/client=([^\s\[]+)\[(?:IPv6:)?([0-9a-fA-F.:]+)\]/))
        rec[:client_host] = c[1]
        rec[:client_ip]   = c[2]
      end
    when "cleanup"
      if (id = rest[/message-id=(\S+?)\s*\z/, 1] || rest[/message-id=(<[^>]*>)/, 1])
        rec[:message_id] = id
      end
    when "qmgr"
      if rest.strip == "removed"
        rec[:removed] = true
      elsif (f = rest.match(/from=<([^>]*)>/))
        rec[:from]  = f[1]
        rec[:size]  = rest[/size=(\d+)/, 1]&.to_i
        rec[:nrcpt] = rest[/nrcpt=(\d+)/, 1]&.to_i
      end
    when "smtp", "lmtp"
      rec[:recipients] << parse_outcome(rest, local: daemon == "lmtp")
    when "bounce"
      # Bounce DSN generated — informational; no extra fact recorded in v1.
    end
  end

  def new_record(qid, ts)
    {
      queue_id: qid, time: ts, client_host: nil, client_ip: nil,
      from: nil, message_id: nil, size: nil, nrcpt: nil,
      recipients: [], removed: false, verdict: nil
    }
  end

  def parse_outcome(rest, local:)
    relay = rest[/relay=([^,]+)/, 1].to_s.strip
    relay_host = relay[/\A([^\[\s]+)/, 1]
    relay_ip   = relay[/\[(?:IPv6:)?([0-9a-fA-F.:]+)\]/, 1]
    is_local   = local || relay.include?("dovecot") || relay.include?("/dovecot-lmtp")
    {
      to:         rest[/to=<([^>]*)>/, 1],
      relay_host: relay_host,
      relay_ip:   relay_ip,
      local:      is_local,
      delay_s:    rest[/\bdelay=([\d.]+)/, 1]&.to_f,
      dsn:        rest[/\bdsn=([\d.]+)/, 1],
      status:     rest[/\bstatus=(\w+)/, 1],
      reply:      rest[/status=\w+\s+\((.*)\)\s*\z/, 1],
      reason:     decode_reason(rest[/\bdsn=([\d.]+)/, 1], rest[/status=\w+\s+\((.*)\)\s*\z/, 1])
    }
  end

  def parse_rejection(payload, ts)
    m = payload.match(/from\s+([^\s\[]+)\[(?:IPv6:)?([0-9a-fA-F.:]+)\]:\s*(.*)\z/)
    return nil unless m
    body = m[3]
    reply = body.split(/;\s*from=/, 2).first.to_s.strip
    {
      client_host: m[1],
      client_ip:   m[2],
      code:        reply[/\b([45]\d\d)\b/, 1],
      dsn:         reply[/\b([45]\.\d+\.\d+)\b/, 1],
      from:        body[/from=<([^>]*)>/, 1],
      to:          body[/to=<([^>]*)>/, 1],
      reply:       reply,
      reason:      decode_reason(reply[/\b([45]\.\d+\.\d+)\b/, 1], reply),
      time:        ts
    }
  end

  # Best-effort: map enhanced DSN (X.Y.Z) first, then the basic SMTP code.
  # The raw reply is always shown alongside, so a miss never hides anything.
  def decode_reason(dsn, reply)
    text = reply.to_s
    code = text[/\b([245]\d\d)\b/, 1]
    if dsn&.start_with?("5.1.1", "5.1.0") || text.match?(/user unknown|no such user|does not exist|recipient address rejected/i)
      "Recipient mailbox doesn't exist at the receiving server"
    elsif dsn&.start_with?("5.1.2")
      "Recipient domain doesn't exist / bad MX"
    elsif dsn == "5.2.2" || dsn == "4.2.2" || text.match?(/mailbox full|over\s?quota/i)
      "Recipient mailbox is full (over quota)"
    elsif dsn&.start_with?("5.7.25", "5.7.26")
      "Rejected — sender IP reverse-DNS / DMARC / authentication policy"
    elsif dsn&.start_with?("5.7", "4.7") && text.match?(/greylist|try again|rate/i)
      "Greylisted or rate-limited — temporary, will retry"
    elsif code == "421" || text.match?(/greylist|try again later|rate limit/i)
      "Greylisted or rate-limited — temporary, will retry"
    elsif dsn&.start_with?("5.7") || text.match?(/blocked|spam|blacklist|blocklist|policy|denied|reputation/i)
      "Rejected by recipient policy (spam / blocklist / policy)"
    elsif (dsn&.start_with?("4.4") || text.match?(/timed out|timeout|connection refused|no route|unable to connect|conversation timed out/i)) && !dsn&.start_with?("5")
      "Could not connect to recipient server — temporary, will retry"
    elsif dsn&.start_with?("4.3", "5.3")
      "Receiving mail system error (problem on their side)"
    elsif dsn == "2.0.0" || code == "250"
      "Accepted by the receiving server"
    elsif code&.start_with?("5") || dsn&.start_with?("5")
      "Permanent failure (recipient server refused) — see raw reply"
    elsif code&.start_with?("4") || dsn&.start_with?("4")
      "Temporary failure (will retry) — see raw reply"
    end
  end

  # bounced > deferred > sent. No recipients (qid seen, no delivery line) =>
  # INCOMPLETE so a truncated paste never reads as delivered.
  def verdict_for(rec)
    statuses = rec[:recipients].map { |r| r[:status] }.compact
    return "INCOMPLETE" if statuses.empty?
    return "BOUNCED"    if statuses.include?("bounced")
    return "DEFERRED"   if statuses.include?("deferred")
    return "DELIVERED"  if statuses.all? { |s| s == "sent" }
    "INCOMPLETE"
  end
end
