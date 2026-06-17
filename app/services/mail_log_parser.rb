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

    @raw.gsub("\r\n", "\n").each_line do |line|
      line = line.chomp
      next if line.strip.empty?

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
      reason:     nil # populated in a later task
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
      reason:      nil, # populated in a later task
      time:        ts
    }
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
