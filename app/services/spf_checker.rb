require "dnsruby"

class SpfChecker
  TIMEOUT = 10.seconds

  # Issue severity levels
  SEVERITY_CRITICAL = "critical"
  SEVERITY_WARNING = "warning"
  SEVERITY_INFO = "info"

  # SPF mechanism types
  MECHANISMS = %w[all include a mx ptr ip4 ip6 exists].freeze
  MODIFIERS = %w[redirect exp].freeze

  # Maximum DNS lookups allowed by RFC 7208
  MAX_DNS_LOOKUPS = 10

  def self.check(domain)
    new(domain).check
  end

  def initialize(domain)
    @domain = domain.to_s.strip.downcase
  end

  def check
    cache_key = "spf:#{@domain}"
    cached_result = Rails.cache.read(cache_key)
    return cached_result if cached_result

    result = {
      success: false,
      domain: @domain,
      record: nil,
      raw_record: nil,
      version: nil,
      mechanisms: [],
      modifiers: [],
      all_mechanism: nil,
      dns_lookup_count: 0,
      includes: [],
      issues: [],
      error: nil,
      checked_at: Time.current.iso8601
    }

    begin
      # Fetch SPF record (TXT record starting with v=spf1)
      spf_records = fetch_spf_records
      
      if spf_records.empty?
        result[:error] = "No SPF record found"
        result[:issues] << {
          severity: SEVERITY_WARNING,
          code: "no_spf",
          title: "No SPF Record",
          message: "No SPF record found for #{@domain}.",
          recommendation: "Add an SPF record to specify which servers can send email for your domain."
        }
      elsif spf_records.length > 1
        result[:error] = "Multiple SPF records found"
        result[:issues] << {
          severity: SEVERITY_CRITICAL,
          code: "multiple_spf",
          title: "Multiple SPF Records",
          message: "Found #{spf_records.length} SPF records. Only one is allowed.",
          recommendation: "Remove duplicate SPF records. Combine them into a single record if needed."
        }
        result[:raw_record] = spf_records.join(" | ")
      else
        result[:success] = true
        result[:raw_record] = spf_records.first
        
        # Parse the SPF record
        parsed = parse_spf_record(spf_records.first)
        result.merge!(parsed)
        
        # Detect issues
        result[:issues] = detect_issues(result)
      end
    rescue Dnsruby::NXDomain
      result[:error] = "Domain does not exist"
      result[:issues] << {
        severity: SEVERITY_CRITICAL,
        code: "nxdomain",
        title: "Domain Does Not Exist",
        message: "The domain #{@domain} does not exist in DNS.",
        recommendation: "Verify the domain name is correct."
      }
    rescue Dnsruby::ResolvTimeout
      result[:error] = "DNS query timed out"
    rescue StandardError => e
      result[:error] = "Error checking SPF: #{e.message}"
    end

    # Cache successful results for 1 hour
    Rails.cache.write(cache_key, result, expires_in: 1.hour) if result[:success]

    result
  end

  private

  def fetch_spf_records
    resolver = Dnsruby::Resolver.new(
      nameserver: "8.8.8.8",
      timeout: TIMEOUT
    )

    response = resolver.query(@domain, Dnsruby::Types::TXT)
    
    spf_records = []
    response.answer.each do |record|
      next unless record.type == Dnsruby::Types::TXT
      
      txt_value = record.strings.join
      if txt_value.downcase.start_with?("v=spf1")
        spf_records << txt_value
      end
    end

    spf_records
  rescue Dnsruby::NXDomain
    []
  end

  def parse_spf_record(record)
    result = {
      record: record,
      version: nil,
      mechanisms: [],
      modifiers: [],
      all_mechanism: nil,
      dns_lookup_count: 0,
      includes: []
    }

    parts = record.split(/\s+/)
    
    parts.each do |part|
      part = part.strip
      next if part.empty?

      # Version
      if part.downcase.start_with?("v=")
        result[:version] = part.split("=", 2).last
        next
      end

      # Parse qualifier (+ - ~ ?)
      qualifier = "+"
      if part.match?(/^[+\-~?]/)
        qualifier = part[0]
        part = part[1..]
      end

      # Check for modifier (redirect=, exp=)
      if part.include?("=") && !part.start_with?("ip4:", "ip6:")
        modifier_name, modifier_value = part.split("=", 2)
        result[:modifiers] << {
          name: modifier_name,
          value: modifier_value
        }
        
        # redirect counts as a DNS lookup
        if modifier_name == "redirect"
          result[:dns_lookup_count] += 1
        end
        next
      end

      # Parse mechanism
      mechanism_type = nil
      mechanism_value = nil

      if part.include?(":")
        mechanism_type, mechanism_value = part.split(":", 2)
      elsif part.include?("/")
        # ip4 or ip6 with CIDR
        if part.match?(/^ip[46]/)
          mechanism_type = part[0..2]
          mechanism_value = part[3..]
        else
          mechanism_type = part.split("/").first
          mechanism_value = part
        end
      else
        mechanism_type = part
      end

      mechanism_type = mechanism_type.downcase if mechanism_type

      mechanism = {
        type: mechanism_type,
        qualifier: qualifier,
        value: mechanism_value
      }

      result[:mechanisms] << mechanism

      # Track 'all' mechanism
      if mechanism_type == "all"
        result[:all_mechanism] = mechanism
      end

      # Track includes
      if mechanism_type == "include"
        result[:includes] << mechanism_value
        result[:dns_lookup_count] += 1
      end

      # Count DNS lookups (a, mx, ptr, exists, include)
      if %w[a mx ptr exists].include?(mechanism_type)
        result[:dns_lookup_count] += 1
      end
    end

    result
  end

  def detect_issues(result)
    issues = []

    # Check version
    if result[:version] != "spf1"
      issues << {
        severity: SEVERITY_WARNING,
        code: "invalid_spf_version",
        title: "Invalid SPF Version",
        message: "SPF version '#{result[:version]}' is not recognized. Expected 'spf1'.",
        recommendation: "Ensure the SPF record starts with 'v=spf1'."
      }
    end

    # Check for 'all' mechanism
    unless result[:all_mechanism]
      issues << {
        severity: SEVERITY_WARNING,
        code: "missing_all",
        title: "Missing 'all' Mechanism",
        message: "SPF record does not end with an 'all' mechanism.",
        recommendation: "Add '-all' (fail), '~all' (softfail), or '?all' (neutral) at the end."
      }
    else
      case result[:all_mechanism][:qualifier]
      when "+"
        issues << {
          severity: SEVERITY_CRITICAL,
          code: "permissive_all",
          title: "Permissive SPF (+all)",
          message: "SPF record uses '+all' which allows any server to send email.",
          recommendation: "Change to '-all' or '~all' to restrict unauthorized senders."
        }
      when "?"
        issues << {
          severity: SEVERITY_WARNING,
          code: "neutral_all",
          title: "Neutral SPF (?all)",
          message: "SPF record uses '?all' which provides no protection.",
          recommendation: "Consider using '-all' or '~all' for better protection."
        }
      when "~"
        issues << {
          severity: SEVERITY_INFO,
          code: "softfail_all",
          title: "SPF Softfail (~all)",
          message: "SPF record uses '~all' (softfail). Unauthorized emails may still be delivered.",
          recommendation: "Consider changing to '-all' for stricter enforcement once you've verified all legitimate senders."
        }
      end
    end

    # Check DNS lookup count
    if result[:dns_lookup_count] > MAX_DNS_LOOKUPS
      issues << {
        severity: SEVERITY_CRITICAL,
        code: "too_many_lookups",
        title: "Too Many DNS Lookups",
        message: "SPF record requires #{result[:dns_lookup_count]} DNS lookups (max: #{MAX_DNS_LOOKUPS}).",
        recommendation: "Reduce the number of 'include', 'a', 'mx', 'ptr', and 'exists' mechanisms."
      }
    elsif result[:dns_lookup_count] > 7
      issues << {
        severity: SEVERITY_WARNING,
        code: "many_lookups",
        title: "Many DNS Lookups",
        message: "SPF record requires #{result[:dns_lookup_count]} DNS lookups (max: #{MAX_DNS_LOOKUPS}).",
        recommendation: "Consider reducing DNS lookups to leave room for future changes."
      }
    end

    # Check for ptr mechanism (deprecated)
    if result[:mechanisms].any? { |m| m[:type] == "ptr" }
      issues << {
        severity: SEVERITY_WARNING,
        code: "ptr_mechanism",
        title: "Deprecated 'ptr' Mechanism",
        message: "SPF record uses the 'ptr' mechanism which is deprecated and slow.",
        recommendation: "Replace 'ptr' with 'a' or 'ip4'/'ip6' mechanisms."
      }
    end

    # Check record length
    if result[:raw_record] && result[:raw_record].length > 255
      issues << {
        severity: SEVERITY_INFO,
        code: "long_record",
        title: "Long SPF Record",
        message: "SPF record is #{result[:raw_record].length} characters. Records over 255 chars need multiple strings.",
        recommendation: "Most DNS providers handle this automatically, but verify the record is published correctly."
      }
    end

    # Check for common misconfigurations
    if result[:includes].empty? && result[:mechanisms].none? { |m| %w[a mx ip4 ip6].include?(m[:type]) }
      issues << {
        severity: SEVERITY_INFO,
        code: "empty_spf",
        title: "SPF Record Has No Mechanisms",
        message: "SPF record doesn't authorize any mail servers (except 'all').",
        recommendation: "Add mechanisms to authorize your email servers (include, a, mx, ip4, ip6)."
      }
    end

    issues
  end
end

