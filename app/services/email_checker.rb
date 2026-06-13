class EmailChecker
  # Issue severity levels
  SEVERITY_CRITICAL = "critical"
  SEVERITY_WARNING = "warning"
  SEVERITY_INFO = "info"

  def self.check(domain, mx_records: nil)
    new(domain, mx_records).check
  end

  def initialize(domain, mx_records = nil)
    @domain = domain.to_s.strip.downcase
    @mx_records = mx_records
  end

  def check
    cache_key = "email:#{@domain}"
    cached_result = Rails.cache.read(cache_key)
    return cached_result if cached_result

    result = {
      success: false,
      domain: @domain,
      has_mx: false,
      mx_records: @mx_records || [],
      spf: nil,
      dkim: nil,
      dmarc: nil,
      authentication_score: 0,
      authentication_grade: "F",
      issues: [],
      recommendations: [],
      checked_at: Time.current.iso8601
    }

    begin
      # Check if domain has MX records (can receive email)
      result[:has_mx] = @mx_records.present? && @mx_records.any?

      # Run all email authentication checks
      result[:spf] = SpfChecker.check(@domain)
      result[:dkim] = DkimChecker.check(@domain)
      result[:dmarc] = DmarcChecker.check(@domain)

      # Calculate authentication score and grade
      score_result = calculate_authentication_score(result)
      result[:authentication_score] = score_result[:score]
      result[:authentication_grade] = score_result[:grade]

      # Aggregate issues from all checkers
      result[:issues] = aggregate_issues(result)

      # Generate recommendations
      result[:recommendations] = generate_recommendations(result)

      result[:success] = true
    rescue StandardError => e
      result[:error] = "Error checking email authentication: #{e.message}"
    end

    # Cache successful results for 1 hour
    Rails.cache.write(cache_key, result, expires_in: 1.hour) if result[:success]

    result
  end

  private

  def calculate_authentication_score(result)
    score = 0
    max_score = 100

    # SPF (30 points max)
    if result[:spf]&.dig(:success)
      spf = result[:spf]
      score += 10 # Has SPF record

      # Check SPF policy strictness
      all_mech = spf[:all_mechanism]
      if all_mech
        case all_mech[:qualifier]
        when "-" then score += 20  # -all (reject)
        when "~" then score += 15  # ~all (softfail)
        when "?" then score += 5   # ?all (neutral)
          # +all gets 0
        end
      end
    end

    # DKIM (30 points max)
    if result[:dkim]&.dig(:success) && result[:dkim][:selectors_found].present?
      score += 20 # Has DKIM records

      # Check DKIM key strength
      valid_keys = result[:dkim][:selectors_found].count do |sel|
        key = sel.dig(:parsed, :public_key)
        key && key.length >= 100
      end
      score += 10 if valid_keys > 0
    end

    # DMARC (40 points max)
    if result[:dmarc]&.dig(:success)
      dmarc = result[:dmarc]
      score += 10 # Has DMARC record

      # Check DMARC policy
      case dmarc[:policy]
      when "reject" then score += 20
      when "quarantine" then score += 15
      when "none" then score += 5
      end

      # Reporting configured
      score += 5 if dmarc[:rua].present?

      # Full percentage
      score += 5 if dmarc[:percentage] == 100
    end

    # Determine grade
    grade = case score
    when 90..100 then "A"
    when 80..89 then "B"
    when 70..79 then "C"
    when 60..69 then "D"
    else "F"
    end

    { score: score, grade: grade }
  end

  def aggregate_issues(result)
    issues = []

    # Add issues from each checker
    issues.concat(result[:spf][:issues] || []) if result[:spf]
    issues.concat(result[:dkim][:issues] || []) if result[:dkim]
    issues.concat(result[:dmarc][:issues] || []) if result[:dmarc]

    # Add cross-checker issues
    issues.concat(detect_cross_issues(result))

    # Sort by severity
    issues.sort_by { |i| { "critical" => 0, "warning" => 1, "info" => 2 }[i[:severity] || i["severity"]] || 3 }
  end

  def detect_cross_issues(result)
    issues = []

    spf_ok = result[:spf]&.dig(:success)
    dkim_ok = result[:dkim]&.dig(:success) && result[:dkim][:selectors_found].present?
    dmarc_ok = result[:dmarc]&.dig(:success)

    # No email authentication at all
    if !spf_ok && !dkim_ok && !dmarc_ok
      issues << {
        severity: SEVERITY_CRITICAL,
        code: "no_email_auth",
        title: "No Email Authentication",
        message: "Domain has no SPF, DKIM, or DMARC records configured.",
        recommendation: "Configure email authentication to prevent spoofing and improve deliverability."
      }
    end

    # DMARC without SPF and DKIM
    if dmarc_ok && !spf_ok && !dkim_ok
      issues << {
        severity: SEVERITY_WARNING,
        code: "dmarc_without_auth",
        title: "DMARC Without SPF/DKIM",
        message: "DMARC is configured but neither SPF nor DKIM are set up.",
        recommendation: "DMARC requires SPF and/or DKIM to authenticate emails effectively."
      }
    end

    # Strong DMARC but weak SPF
    if dmarc_ok && spf_ok
      dmarc_policy = result[:dmarc][:policy]
      spf_all = result[:spf][:all_mechanism]

      if dmarc_policy == "reject" && spf_all && %w[+ ?].include?(spf_all[:qualifier])
        issues << {
          severity: SEVERITY_WARNING,
          code: "mismatched_policies",
          title: "Mismatched SPF/DMARC Policies",
          message: "DMARC rejects failures, but SPF allows all senders.",
          recommendation: "Align SPF with DMARC by using -all or ~all."
        }
      end
    end

    # Has MX but no SPF
    if result[:has_mx] && !spf_ok
      issues << {
        severity: SEVERITY_WARNING,
        code: "mx_without_spf",
        title: "MX Records Without SPF",
        message: "Domain can receive email but has no SPF record to authorize senders.",
        recommendation: "Add an SPF record to specify which servers can send email for this domain."
      }
    end

    issues
  end

  def generate_recommendations(result)
    recommendations = []

    spf_ok = result[:spf]&.dig(:success)
    dkim_ok = result[:dkim]&.dig(:success) && result[:dkim][:selectors_found].present?
    dmarc_ok = result[:dmarc]&.dig(:success)

    # Priority 1: Set up basics
    unless spf_ok
      recommendations << {
        priority: 1,
        title: "Add SPF Record",
        description: "Create an SPF record to specify authorized email senders.",
        example: "v=spf1 include:_spf.google.com ~all"
      }
    end

    unless dkim_ok
      recommendations << {
        priority: 2,
        title: "Configure DKIM",
        description: "Set up DKIM signing with your email provider.",
        example: "Contact your email provider for DKIM setup instructions."
      }
    end

    unless dmarc_ok
      recommendations << {
        priority: 3,
        title: "Add DMARC Record",
        description: "Start with a monitoring policy to receive reports.",
        example: "v=DMARC1; p=none; rua=mailto:dmarc@#{@domain}"
      }
    end

    # Priority 2: Strengthen existing configuration
    if dmarc_ok && result[:dmarc][:policy] == "none"
      recommendations << {
        priority: 4,
        title: "Strengthen DMARC Policy",
        description: "After analyzing reports, upgrade from p=none to p=quarantine.",
        example: "v=DMARC1; p=quarantine; rua=mailto:dmarc@#{@domain}"
      }
    end

    if dmarc_ok && result[:dmarc][:policy] == "quarantine"
      recommendations << {
        priority: 5,
        title: "Move to DMARC Reject",
        description: "For maximum protection, upgrade to p=reject.",
        example: "v=DMARC1; p=reject; rua=mailto:dmarc@#{@domain}"
      }
    end

    if spf_ok && result[:spf][:all_mechanism]
      qual = result[:spf][:all_mechanism][:qualifier]
      if qual == "~"
        recommendations << {
          priority: 5,
          title: "Harden SPF Policy",
          description: "Change ~all (softfail) to -all (fail) for stricter enforcement.",
          example: "Change the end of your SPF record from ~all to -all"
        }
      end
    end

    recommendations.sort_by { |r| r[:priority] }
  end
end
