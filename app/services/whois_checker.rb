require "ipaddr"
require "whois"
require "shellwords"

class WhoisChecker
  TIMEOUT = 20.seconds  # Generous timeout for slow registrar WHOIS servers
  MAX_RETRIES = 2

  # Issue severity levels
  SEVERITY_CRITICAL = "critical"  # Red - immediate action needed
  SEVERITY_WARNING = "warning"    # Yellow - attention recommended
  SEVERITY_INFO = "info"          # Blue - informational

  def self.check(domain)
    new(domain).check
  end

  def initialize(domain)
    @domain = domain.to_s.strip.downcase
    @record_type = ip?(@domain) ? :ip : :domain
  end

  def ip?(value)
    IPAddr.new(value)
    true
  rescue IPAddr::Error
    false
  end

  def check
    cache_key = "whois:#{@domain}"
    cached_result = Rails.cache.read(cache_key)
    return cached_result if cached_result

    result = {
      success: false,
      record_type: @record_type,
      source: :whois_fallback,
      registrar: nil,
      expiration_date: nil,
      creation_date: nil,
      updated_date: nil,
      nameservers: [],
      registrant: nil,
      ip_range: nil,
      cidr: nil,
      network_name: nil,
      organization: nil,
      country: nil,
      abuse_contact: nil,
      raw_data: nil,
      error: nil,
      issues: []
    }

    retries = 0
    begin
      client = Whois::Client.new(timeout: TIMEOUT)
      whois_record = client.lookup(@domain)

      result[:success] = true
      result[:raw_data] = whois_record.content

      if @record_type == :ip
        extract_ip_fields!(result, whois_record.content.to_s)
      else
        result[:registrar] = extract_registrar(whois_record)
        result[:expiration_date] = extract_expiration_date(whois_record)
        result[:creation_date] = extract_creation_date(whois_record)
        result[:updated_date] = extract_updated_date(whois_record)
        result[:nameservers] = extract_nameservers(whois_record)
        result[:registrant] = extract_registrant(whois_record)
        result[:issues] = detect_issues(result)
      end
    rescue Timeout::Error, Errno::ETIMEDOUT => e
      retries += 1
      if retries < MAX_RETRIES
        sleep(1)  # Brief pause before retry
        retry
      end
      result[:error] = "WHOIS lookup timed out after #{MAX_RETRIES} attempts"
      result[:issues] << {
        severity: SEVERITY_WARNING,
        code: "whois_timeout",
        title: "WHOIS Lookup Timed Out",
        message: "The WHOIS server did not respond after #{MAX_RETRIES} attempts (#{TIMEOUT}s timeout each).",
        recommendation: "The registrar's WHOIS server may be slow or unavailable. Try again later or check the domain manually at whois.domaintools.com."
      }
    rescue Whois::ConnectionError => e
      retries += 1
      if retries < MAX_RETRIES
        sleep(1)
        retry
      end
      result[:error] = "WHOIS connection error: #{e.message}"
      result[:issues] << {
        severity: SEVERITY_WARNING,
        code: "whois_connection_error",
        title: "WHOIS Connection Failed",
        message: "Could not connect to the WHOIS server after #{MAX_RETRIES} attempts.",
        recommendation: "Check your network connection or try again later."
      }
    rescue Whois::ServerError => e
      result[:error] = "WHOIS server error: #{e.message}"
      result[:issues] << {
        severity: SEVERITY_WARNING,
        code: "whois_server_error",
        title: "WHOIS Server Error",
        message: "The WHOIS server returned an error.",
        recommendation: "The WHOIS server may be temporarily unavailable. Try again later."
      }
    rescue Whois::NoInterfaceError, Whois::WebInterfaceError => e
      result[:error] = "WHOIS interface not available for this TLD"
      result[:issues] << {
        severity: SEVERITY_INFO,
        code: "whois_no_interface",
        title: "WHOIS Not Available",
        message: "WHOIS lookup is not available for this domain's TLD.",
        recommendation: "Some TLDs do not provide public WHOIS data. Check with the registry directly."
      }
    rescue Whois::Error => e
      result[:error] = "WHOIS error: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      retries += 1
      if retries < MAX_RETRIES
        sleep(1)
        retry
      end
      result[:error] = "Network error: #{e.message}"
      result[:issues] << {
        severity: SEVERITY_WARNING,
        code: "whois_network_error",
        title: "Network Error",
        message: "Could not reach the WHOIS server after #{MAX_RETRIES} attempts.",
        recommendation: "Check your network connection and try again."
      }
    rescue StandardError => e
      result[:error] = "Unexpected error: #{e.message}"
    end

    # Cache successful results for 24 hours
    Rails.cache.write(cache_key, result, expires_in: 24.hours) if result[:success]

    result
  end

  private

  def detect_issues(result)
    issues = []

    # Check expiration date
    if result[:expiration_date].present?
      begin
        expiry = Date.parse(result[:expiration_date])
        days_until_expiry = (expiry - Date.today).to_i

        if days_until_expiry < 0
          issues << {
            severity: SEVERITY_CRITICAL,
            code: "domain_expired",
            title: "Domain Expired",
            message: "This domain expired #{days_until_expiry.abs} days ago on #{expiry.strftime('%B %d, %Y')}.",
            recommendation: "Renew immediately to prevent loss of the domain."
          }
        elsif days_until_expiry <= 7
          issues << {
            severity: SEVERITY_CRITICAL,
            code: "expiring_very_soon",
            title: "Expiring Very Soon",
            message: "Domain expires in #{days_until_expiry} days on #{expiry.strftime('%B %d, %Y')}.",
            recommendation: "Renew immediately to avoid service disruption."
          }
        elsif days_until_expiry <= 30
          issues << {
            severity: SEVERITY_WARNING,
            code: "expiring_soon",
            title: "Expiring Soon",
            message: "Domain expires in #{days_until_expiry} days on #{expiry.strftime('%B %d, %Y')}.",
            recommendation: "Schedule renewal to ensure continuity."
          }
        elsif days_until_expiry <= 90
          issues << {
            severity: SEVERITY_INFO,
            code: "expiring_in_90_days",
            title: "Renewal Reminder",
            message: "Domain expires in #{days_until_expiry} days on #{expiry.strftime('%B %d, %Y')}.",
            recommendation: "Consider setting up auto-renewal if not already enabled."
          }
        end
      rescue ArgumentError
        # Date parsing failed, skip expiration check
      end
    else
      issues << {
        severity: SEVERITY_INFO,
        code: "no_expiration_date",
        title: "Expiration Date Unknown",
        message: "Could not determine the domain expiration date from WHOIS data.",
        recommendation: "Check with your registrar for accurate expiration information."
      }
    end

    # Check nameservers
    if result[:nameservers].empty?
      issues << {
        severity: SEVERITY_WARNING,
        code: "no_nameservers",
        title: "No Nameservers Found",
        message: "No nameservers were found in the WHOIS data.",
        recommendation: "Verify nameserver configuration with your registrar."
      }
    elsif result[:nameservers].length == 1
      issues << {
        severity: SEVERITY_WARNING,
        code: "single_nameserver",
        title: "Single Nameserver",
        message: "Only one nameserver is configured, which provides no redundancy.",
        recommendation: "Add at least one additional nameserver for reliability."
      }
    end

    # Check registrar
    if result[:registrar].blank?
      issues << {
        severity: SEVERITY_INFO,
        code: "no_registrar",
        title: "Registrar Unknown",
        message: "Could not determine the domain registrar from WHOIS data.",
        recommendation: "This may be normal for some TLDs with privacy-protected WHOIS."
      }
    end

    issues
  end

  private

  # IP/network WHOIS uses a different schema than domain WHOIS (ARIN/RIPE/etc.).
  # Extract the network-ownership fields the RDAP IP path also surfaces.
  def extract_ip_fields!(result, content)
    result[:cidr]          = content[/CIDR:\s*(.+)/i, 1]&.strip
    result[:network_name]  = content[/NetName:\s*(.+)/i, 1]&.strip
    result[:organization]  = content[/(?:Organization|OrgName|org-name|owner):\s*(.+)/i, 1]&.strip
    result[:country]       = content[/Country:\s*(.+)/i, 1]&.strip
    result[:abuse_contact] = content[/(?:OrgAbuseEmail|abuse-mailbox|e-mail):\s*(\S+@\S+)/i, 1]&.strip
    net = content[/NetRange:\s*(.+)/i, 1] || content[/inetnum:\s*(.+)/i, 1]
    result[:ip_range]      = net&.strip
    result[:issues]        = []
  end

  def extract_registrar(whois_record)
    content = whois_record.content.to_s
    registrar_match = content.match(/Registrar:\s*(.+)/i) ||
                      content.match(/Registrar Name:\s*(.+)/i) ||
                      content.match(/Registrar Organization:\s*(.+)/i)
    registrar_match ? registrar_match[1].strip : nil
  rescue StandardError
    nil
  end

  def extract_expiration_date(whois_record)
    content = whois_record.content.to_s
    expiry_match = content.match(/Expir(?:ation|y) Date:\s*(.+)/i) ||
                   content.match(/Registry Expiry Date:\s*(.+)/i) ||
                   content.match(/paid-till:\s*(.+)/i)

    if expiry_match
      date_str = expiry_match[1].strip
      Date.parse(date_str).iso8601 rescue date_str
    end
  rescue StandardError
    nil
  end

  def extract_creation_date(whois_record)
    content = whois_record.content.to_s
    creation_match = content.match(/Creation Date:\s*(.+)/i) ||
                     content.match(/Created Date:\s*(.+)/i) ||
                     content.match(/Created:\s*(.+)/i) ||
                     content.match(/Registration Date:\s*(.+)/i)

    if creation_match
      date_str = creation_match[1].strip
      Date.parse(date_str).iso8601 rescue date_str
    end
  rescue StandardError
    nil
  end

  def extract_updated_date(whois_record)
    content = whois_record.content.to_s
    updated_match = content.match(/Updated Date:\s*(.+)/i) ||
                    content.match(/Last Updated:\s*(.+)/i) ||
                    content.match(/Modified:\s*(.+)/i)

    if updated_match
      date_str = updated_match[1].strip
      Date.parse(date_str).iso8601 rescue date_str
    end
  rescue StandardError
    nil
  end

  def extract_nameservers(whois_record)
    content = whois_record.content.to_s
    nameservers = []

    content.scan(/Name Server:\s*(\S+)/i).each do |match|
      nameservers << match[0].strip.downcase
    end

    content.scan(/Nameserver:\s*(\S+)/i).each do |match|
      ns = match[0].strip.downcase
      nameservers << ns unless nameservers.include?(ns)
    end

    content.scan(/nserver:\s*(\S+)/i).each do |match|
      ns = match[0].strip.downcase
      nameservers << ns unless nameservers.include?(ns)
    end

    nameservers.uniq
  rescue StandardError
    []
  end

  def extract_registrant(whois_record)
    content = whois_record.content.to_s
    registrant_match = content.match(/Registrant Organization:\s*(.+)/i) ||
                       content.match(/Registrant Name:\s*(.+)/i) ||
                       content.match(/Registrant:\s*(.+)/i)
    registrant_match ? registrant_match[1].strip : nil
  rescue StandardError
    nil
  end
end

