require "net/smtp"
require "uri"
require "set"

# Validates an email address: format, MX/A deliverability, disposable-domain, and a
# best-effort SMTP mailbox probe. Pure Ruby (reuses DnsChecker). Never raises.
# The #smtp_probe seam is stubbed in tests (no real SMTP/DNS).
class EmailValidityChecker
  FORMAT_RE       = URI::MailTo::EMAIL_REGEXP
  DISPOSABLE_PATH = Rails.root.join("config", "disposable_email_domains.txt")
  SMTP_TIMEOUT    = 5

  def self.disposable_domains
    @disposable_domains ||=
      if File.exist?(DISPOSABLE_PATH)
        File.readlines(DISPOSABLE_PATH, chomp: true).map { |l| l.strip.downcase }.reject(&:empty?).to_set
      else
        Set.new
      end
  end

  def self.check(email) = new(email).check

  def initialize(email)
    @email = email.to_s.strip
  end

  def check
    local, _at, domain = @email.rpartition("@")
    valid_format = @email.match?(FORMAT_RE) && !domain.empty?

    unless valid_format
      return base.merge(
        valid_format: false,
        issues: [issue("critical", "invalid_format", "Invalid email format",
                       "#{@email.presence || '(empty)'} is not a valid email address.",
                       "Check for typos / a missing @ or domain.")]
      )
    end

    dns         = ::DnsChecker.check(domain)
    mx          = Array(dns[:mx_records]).sort_by { |m| ((m[:priority] || m["priority"]) || Float::INFINITY).to_i }
    mx_hosts    = mx.map { |m| (m[:host] || m["host"]).to_s.chomp(".") }.reject(&:empty?)
    deliverable = mx_hosts.any? || Array(dns[:a_records]).any?
    disposable  = self.class.disposable_domains.include?(domain.downcase)
    smtp        = (deliverable && mx_hosts.any?) ? smtp_probe(mx_hosts.first, @email).to_s : "skipped"

    result = base.merge(
      local: local, domain: domain, valid_format: true,
      deliverable: deliverable, mx_hosts: mx_hosts, disposable: disposable,
      smtp: smtp, smtp_detail: smtp_detail(smtp)
    )
    result.merge(issues: build_issues(result))
  rescue StandardError => e
    base.merge(success: false, error: "#{e.class}: #{e.message}")
  end

  private

  def base
    { success: true, email: @email, local: nil, domain: nil, valid_format: nil,
      deliverable: nil, mx_hosts: [], disposable: nil, smtp: "skipped",
      smtp_detail: nil, issues: [], error: nil }
  end

  def smtp_detail(smtp)
    case smtp
    when "exists"       then "Mail server accepted RCPT TO (mailbox appears to exist)."
    when "not_found"    then "Mail server rejected the mailbox (it does not exist)."
    when "inconclusive" then "SMTP unreachable from here — port 25 is likely firewalled; mailbox not verified."
    end
  end

  def build_issues(r)
    issues = []
    unless r[:deliverable]
      issues << issue("critical", "not_deliverable", "Domain cannot receive mail",
                      "#{r[:domain]} has no MX or A record.", "Verify the domain is correct and has mail DNS.")
    end
    if r[:disposable]
      issues << issue("warning", "disposable", "Disposable email domain",
                      "#{r[:domain]} is a known disposable/throwaway provider.", "Treat the address as low-trust.")
    end
    case r[:smtp]
    when "not_found"
      issues << issue("warning", "smtp_no_mailbox", "Mailbox does not exist",
                      "The mail server rejected RCPT TO for this address.", "Confirm the address with the customer.")
    when "inconclusive"
      issues << issue("info", "smtp_inconclusive", "Mailbox not verified",
                      "SMTP was unreachable (port 25 is likely firewalled), so mailbox existence could not be confirmed.",
                      "Re-run from a network that allows outbound port 25 if verification is needed.")
    end
    issues
  end

  def issue(severity, code, title, message, recommendation)
    { "severity" => severity, "code" => code, "title" => title, "message" => message, "recommendation" => recommendation }
  end

  # Seam — stubbed in tests. Returns :exists | :not_found | :inconclusive.
  def smtp_probe(mx_host, email)
    smtp = Net::SMTP.new(mx_host, 25)
    smtp.open_timeout = SMTP_TIMEOUT
    smtp.read_timeout = SMTP_TIMEOUT
    smtp.start("toolharness.local") do |s|
      s.mailfrom("") # null sender: MAIL FROM:<>
      begin
        s.rcptto(email)
        :exists
      rescue Net::SMTPFatalError
        :not_found
      end
    end
  rescue StandardError
    :inconclusive
  end
end
