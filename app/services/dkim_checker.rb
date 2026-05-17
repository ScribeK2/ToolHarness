require "dnsruby"

class DkimChecker
  TIMEOUT = 10.seconds

  # Issue severity levels
  SEVERITY_CRITICAL = "critical"
  SEVERITY_WARNING = "warning"
  SEVERITY_INFO = "info"

  # Common DKIM selectors used by popular email providers
  COMMON_SELECTORS = %w[
    default
    selector1
    selector2
    google
    k1
    k2
    s1
    s2
    dkim
    mail
    email
    mx
    smtp
    mandrill
    mailchimp
    mc
    sendgrid
    sg
    sg1
    sg2
    amazonses
    ses
    mailgun
    mg
    postmark
    pm
    sparkpost
    sp
    zendesk
    zendesk1
    zendesk2
    freshdesk
    intercom
    hubspot
    hs1
    hs2
    salesforce
    sf
    zoho
    protonmail
    mimecast
    m1
  ].freeze

  def self.check(domain, selectors: COMMON_SELECTORS)
    new(domain).check(selectors)
  end

  def initialize(domain)
    @domain = domain.to_s.strip.downcase
  end

  def check(selectors = COMMON_SELECTORS)
    cache_key = "dkim:#{@domain}"
    cached_result = Rails.cache.read(cache_key)
    return cached_result if cached_result

    result = {
      success: false,
      domain: @domain,
      selectors_found: [],
      selectors_checked: selectors.length,
      issues: [],
      error: nil,
      checked_at: Time.current.iso8601
    }

    begin
      resolver = Dnsruby::Resolver.new(
        nameserver: "8.8.8.8",
        timeout: TIMEOUT
      )

      # Check each selector
      selectors.each do |selector|
        dkim_domain = "#{selector}._domainkey.#{@domain}"
        
        begin
          response = resolver.query(dkim_domain, Dnsruby::Types::TXT)
          
          response.answer.each do |record|
            next unless record.type == Dnsruby::Types::TXT
            
            txt_value = record.strings.join
            
            # Check if it's a valid DKIM record (contains v=DKIM1 or p=)
            if txt_value.include?("v=DKIM1") || txt_value.match?(/p=\s*[A-Za-z0-9+\/=]/)
              parsed = parse_dkim_record(txt_value)
              result[:selectors_found] << {
                selector: selector,
                domain: dkim_domain,
                raw_record: txt_value,
                parsed: parsed,
                issues: analyze_dkim_record(selector, parsed)
              }
            end
          end
        rescue Dnsruby::NXDomain
          # Selector doesn't exist, continue to next
        rescue Dnsruby::ResolvTimeout
          # Skip this selector on timeout
        rescue StandardError
          # Skip on any other error
        end
      end

      if result[:selectors_found].any?
        result[:success] = true
      else
        result[:issues] << {
          severity: SEVERITY_INFO,
          code: "no_dkim_found",
          title: "No DKIM Records Found",
          message: "No DKIM records found for common selectors.",
          recommendation: "If you use email, configure DKIM with your email provider's selector."
        }
      end

      # Aggregate issues from found selectors
      result[:selectors_found].each do |selector_info|
        result[:issues].concat(selector_info[:issues] || [])
      end

    rescue StandardError => e
      result[:error] = "Error checking DKIM: #{e.message}"
    end

    # Cache results for 1 hour
    Rails.cache.write(cache_key, result, expires_in: 1.hour) if result[:success]

    result
  end

  private

  def parse_dkim_record(record)
    parsed = {
      version: nil,
      key_type: nil,
      public_key: nil,
      hash_algorithms: nil,
      service_type: nil,
      flags: nil,
      notes: nil
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
        when "v"
          parsed[:version] = value
        when "k"
          parsed[:key_type] = value
        when "p"
          parsed[:public_key] = value
        when "h"
          parsed[:hash_algorithms] = value
        when "s"
          parsed[:service_type] = value
        when "t"
          parsed[:flags] = value
        when "n"
          parsed[:notes] = value
        end
      end
    end

    parsed
  end

  def analyze_dkim_record(selector, parsed)
    issues = []

    # Check version
    if parsed[:version] && parsed[:version] != "DKIM1"
      issues << {
        severity: SEVERITY_WARNING,
        code: "invalid_dkim_version",
        title: "Invalid DKIM Version (#{selector})",
        message: "DKIM version '#{parsed[:version]}' is not recognized.",
        recommendation: "Use 'v=DKIM1' for the version tag."
      }
    end

    # Check public key
    if parsed[:public_key].nil? || parsed[:public_key].empty?
      issues << {
        severity: SEVERITY_CRITICAL,
        code: "missing_dkim_key",
        title: "Missing DKIM Public Key (#{selector})",
        message: "DKIM record for selector '#{selector}' has no public key.",
        recommendation: "This may indicate a revoked key. Verify with your email provider."
      }
    elsif parsed[:public_key].length < 100
      issues << {
        severity: SEVERITY_WARNING,
        code: "short_dkim_key",
        title: "Short DKIM Key (#{selector})",
        message: "DKIM key appears short (#{parsed[:public_key].length} chars). May be a 512-bit key.",
        recommendation: "Use at least 1024-bit keys. 2048-bit is recommended."
      }
    end

    # Check key type
    if parsed[:key_type] && parsed[:key_type] != "rsa"
      issues << {
        severity: SEVERITY_INFO,
        code: "non_rsa_dkim",
        title: "Non-RSA DKIM Key (#{selector})",
        message: "DKIM key uses #{parsed[:key_type]} algorithm.",
        recommendation: "RSA is most widely supported. Ed25519 is newer but less compatible."
      }
    end

    # Check for testing mode
    if parsed[:flags]&.include?("y")
      issues << {
        severity: SEVERITY_WARNING,
        code: "dkim_testing_mode",
        title: "DKIM in Testing Mode (#{selector})",
        message: "DKIM selector '#{selector}' is in testing mode (t=y).",
        recommendation: "Remove the 't=y' flag once testing is complete."
      }
    end

    issues
  end
end

