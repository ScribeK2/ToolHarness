require "dnsruby"

class DmarcChecker
  TIMEOUT = 10.seconds

  # Issue severity levels
  SEVERITY_CRITICAL = "critical"
  SEVERITY_WARNING = "warning"
  SEVERITY_INFO = "info"

  # DMARC policy values
  POLICIES = {
    "none" => { level: 0, description: "Monitor only, no action taken" },
    "quarantine" => { level: 1, description: "Suspicious emails sent to spam" },
    "reject" => { level: 2, description: "Unauthorized emails rejected" }
  }.freeze

  def self.check(domain)
    new(domain).check
  end

  def initialize(domain)
    @domain = domain.to_s.strip.downcase
  end

  def check
    cache_key = "dmarc:#{@domain}"
    cached_result = Rails.cache.read(cache_key)
    return cached_result if cached_result

    result = {
      success: false,
      domain: @domain,
      dmarc_domain: "_dmarc.#{@domain}",
      record: nil,
      raw_record: nil,
      policy: nil,
      subdomain_policy: nil,
      percentage: 100,
      rua: [],
      ruf: [],
      alignment_spf: nil,
      alignment_dkim: nil,
      failure_options: nil,
      report_interval: nil,
      issues: [],
      error: nil,
      checked_at: Time.current.iso8601
    }

    begin
      dmarc_records = fetch_dmarc_record

      if dmarc_records.empty?
        result[:error] = "No DMARC record found"
        result[:issues] << {
          severity: SEVERITY_WARNING,
          code: "no_dmarc",
          title: "No DMARC Record",
          message: "No DMARC record found at _dmarc.#{@domain}.",
          recommendation: "Add a DMARC record to protect against email spoofing and receive reports."
        }
      elsif dmarc_records.length > 1
        result[:error] = "Multiple DMARC records found"
        result[:issues] << {
          severity: SEVERITY_CRITICAL,
          code: "multiple_dmarc",
          title: "Multiple DMARC Records",
          message: "Found #{dmarc_records.length} DMARC records. Only one is allowed.",
          recommendation: "Remove duplicate DMARC records."
        }
        result[:raw_record] = dmarc_records.join(" | ")
      else
        result[:success] = true
        result[:raw_record] = dmarc_records.first

        # Parse the DMARC record
        parsed = parse_dmarc_record(dmarc_records.first)
        result.merge!(parsed)

        # Detect issues
        result[:issues] = detect_issues(result)
      end
    rescue Dnsruby::NXDomain
      result[:error] = "DMARC domain does not exist"
      result[:issues] << {
        severity: SEVERITY_WARNING,
        code: "no_dmarc",
        title: "No DMARC Record",
        message: "No DMARC record found at _dmarc.#{@domain}.",
        recommendation: "Add a DMARC record to protect against email spoofing."
      }
    rescue Dnsruby::ResolvTimeout
      result[:error] = "DNS query timed out"
    rescue StandardError => e
      result[:error] = "Error checking DMARC: #{e.message}"
    end

    # Cache successful results for 1 hour
    Rails.cache.write(cache_key, result, expires_in: 1.hour) if result[:success]

    result
  end

  private

  def fetch_dmarc_record
    resolver = Dnsruby::Resolver.new(
      nameserver: "8.8.8.8",
      timeout: TIMEOUT
    )

    dmarc_domain = "_dmarc.#{@domain}"
    response = resolver.query(dmarc_domain, Dnsruby::Types::TXT)

    dmarc_records = []
    response.answer.each do |record|
      next unless record.type == Dnsruby::Types::TXT

      txt_value = record.strings.join
      if txt_value.downcase.start_with?("v=dmarc1")
        dmarc_records << txt_value
      end
    end

    dmarc_records
  rescue Dnsruby::NXDomain
    []
  end

  def parse_dmarc_record(record)
    result = {
      record: record,
      policy: nil,
      subdomain_policy: nil,
      percentage: 100,
      rua: [],
      ruf: [],
      alignment_spf: "r",  # default: relaxed
      alignment_dkim: "r", # default: relaxed
      failure_options: "0",
      report_interval: 86400,
      report_format: "afrf"
    }

    # Parse key-value pairs
    parts = record.split(";").map(&:strip)

    parts.each do |part|
      next if part.empty?

      if part.include?("=")
        key, value = part.split("=", 2)
        key = key.strip.downcase
        value = value&.strip

        case key
        when "p"
          result[:policy] = value&.downcase
        when "sp"
          result[:subdomain_policy] = value&.downcase
        when "pct"
          result[:percentage] = value.to_i
        when "rua"
          result[:rua] = parse_report_addresses(value)
        when "ruf"
          result[:ruf] = parse_report_addresses(value)
        when "aspf"
          result[:alignment_spf] = value&.downcase
        when "adkim"
          result[:alignment_dkim] = value&.downcase
        when "fo"
          result[:failure_options] = value
        when "ri"
          result[:report_interval] = value.to_i
        when "rf"
          result[:report_format] = value&.downcase
        end
      end
    end

    result
  end

  def parse_report_addresses(value)
    return [] unless value

    value.split(",").map(&:strip).map do |addr|
      # Remove mailto: prefix if present
      addr.gsub(/^mailto:/i, "")
    end
  end

  def detect_issues(result)
    issues = []

    # Check policy
    if result[:policy].nil?
      issues << {
        severity: SEVERITY_CRITICAL,
        code: "missing_policy",
        title: "Missing DMARC Policy",
        message: "DMARC record does not specify a policy (p=).",
        recommendation: "Add a policy: p=none (monitor), p=quarantine, or p=reject."
      }
    elsif result[:policy] == "none"
      issues << {
        severity: SEVERITY_WARNING,
        code: "policy_none",
        title: "DMARC Policy Set to None",
        message: "DMARC policy is 'none' — unauthorized emails won't be blocked.",
        recommendation: "Once you've analyzed reports, upgrade to p=quarantine or p=reject."
      }
    elsif result[:policy] == "quarantine"
      issues << {
        severity: SEVERITY_INFO,
        code: "policy_quarantine",
        title: "DMARC Policy Set to Quarantine",
        message: "Suspicious emails will be sent to spam folders.",
        recommendation: "Consider upgrading to p=reject for maximum protection."
      }
    end

    # Check subdomain policy
    if result[:policy] == "reject" && result[:subdomain_policy].nil?
      issues << {
        severity: SEVERITY_INFO,
        code: "no_subdomain_policy",
        title: "No Subdomain Policy",
        message: "No explicit subdomain policy (sp=). Subdomains inherit the main policy.",
        recommendation: "Consider adding sp=reject to explicitly protect subdomains."
      }
    elsif result[:subdomain_policy] && result[:policy]
      main_level = POLICIES.dig(result[:policy], :level) || 0
      sub_level = POLICIES.dig(result[:subdomain_policy], :level) || 0

      if sub_level < main_level
        issues << {
          severity: SEVERITY_WARNING,
          code: "weak_subdomain_policy",
          title: "Subdomain Policy Weaker Than Main",
          message: "Subdomain policy (#{result[:subdomain_policy]}) is weaker than main policy (#{result[:policy]}).",
          recommendation: "Consider setting sp=#{result[:policy]} or stronger."
        }
      end
    end

    # Check percentage
    if result[:percentage] < 100
      issues << {
        severity: SEVERITY_INFO,
        code: "partial_enforcement",
        title: "Partial DMARC Enforcement",
        message: "DMARC policy only applies to #{result[:percentage]}% of emails.",
        recommendation: "Increase pct to 100 once you've verified legitimate senders pass."
      }
    end

    # Check aggregate reporting
    if result[:rua].empty?
      issues << {
        severity: SEVERITY_WARNING,
        code: "no_aggregate_reports",
        title: "No Aggregate Report Address",
        message: "No rua= address configured for aggregate reports.",
        recommendation: "Add rua=mailto:dmarc@#{@domain} to receive daily reports."
      }
    end

    # Check forensic reporting
    if result[:ruf].empty? && result[:policy] != "none"
      issues << {
        severity: SEVERITY_INFO,
        code: "no_forensic_reports",
        title: "No Forensic Report Address",
        message: "No ruf= address configured for failure reports.",
        recommendation: "Consider adding ruf= for detailed failure reports (note: many providers don't send these)."
      }
    end

    # Check alignment settings
    if result[:alignment_spf] == "r" && result[:alignment_dkim] == "r"
      issues << {
        severity: SEVERITY_INFO,
        code: "relaxed_alignment",
        title: "Relaxed Alignment",
        message: "Both SPF and DKIM use relaxed alignment (subdomains allowed).",
        recommendation: "For stricter security, consider aspf=s and/or adkim=s (strict)."
      }
    end

    # Check for external report domains
    result[:rua].each do |addr|
      report_domain = addr.split("@").last
      if report_domain && report_domain != @domain && !report_domain.end_with?(".#{@domain}")
        issues << {
          severity: SEVERITY_INFO,
          code: "external_rua",
          title: "External Reporting Domain",
          message: "Aggregate reports sent to external domain: #{report_domain}",
          recommendation: "Ensure #{report_domain} has a DMARC report authorization record."
        }
      end
    end

    issues
  end
end
