require "dnsruby"

class DnsChecker
  TIMEOUT = 10.seconds
  RESOLVERS = [
    { name: "Google", address: "8.8.8.8" },
    { name: "Cloudflare", address: "1.1.1.1" }
  ].freeze

  # Issue severity levels
  SEVERITY_CRITICAL = "critical"  # Red - immediate action needed
  SEVERITY_WARNING = "warning"    # Yellow - attention recommended
  SEVERITY_INFO = "info"          # Blue - informational

  def self.check(domain)
    new(domain).check
  end

  def initialize(domain)
    @domain = domain.to_s.strip.downcase
  end

  def check
    cache_key = "dns:#{@domain}"
    cached_result = Rails.cache.read(cache_key)
    return cached_result if cached_result

    result = {
      success: false,
      a_records: [],
      aaaa_records: [],
      mx_records: [],
      cname_records: [],
      ns_records: [],
      txt_records: [],
      errors: [],
      resolver_results: {},
      issues: []
    }

    # Check with multiple resolvers for cross-verification
    resolver_results = RESOLVERS.map do |resolver|
      check_with_resolver(resolver[:name], resolver[:address])
    end

    # Aggregate results
    resolver_results.each do |resolver_result|
      result[:resolver_results][resolver_result[:resolver]] = resolver_result

      if resolver_result[:success]
        result[:success] = true
        result[:a_records].concat(resolver_result[:a_records] || [])
        result[:aaaa_records].concat(resolver_result[:aaaa_records] || [])
        result[:mx_records].concat(resolver_result[:mx_records] || [])
        result[:cname_records].concat(resolver_result[:cname_records] || [])
        result[:ns_records].concat(resolver_result[:ns_records] || [])
        result[:txt_records].concat(resolver_result[:txt_records] || [])
      else
        result[:errors] << "#{resolver_result[:resolver]}: #{resolver_result[:error]}"
      end
    end

    # Deduplicate records
    result[:a_records].uniq!
    result[:aaaa_records].uniq!
    result[:mx_records].uniq!
    result[:cname_records].uniq!
    result[:ns_records].uniq!
    result[:txt_records].uniq!

    # Detect issues after aggregating results
    result[:issues] = detect_issues(result, resolver_results)

    # Cache successful results for 1 hour
    Rails.cache.write(cache_key, result, expires_in: 1.hour) if result[:success]

    result
  end

  private

  def detect_issues(result, resolver_results)
    issues = []

    # Check for NXDOMAIN (domain doesn't exist)
    all_failed = resolver_results.all? { |r| !r[:success] }
    if all_failed && result[:errors].any? { |e| e.include?("NXDomain") || e.include?("does not exist") }
      issues << {
        severity: SEVERITY_CRITICAL,
        code: "nxdomain",
        title: "Domain Does Not Exist",
        message: "DNS servers report this domain does not exist (NXDOMAIN).",
        recommendation: "Verify the domain is registered and DNS is properly configured."
      }
      return issues # No point checking further
    end

    # Check for missing A records
    if result[:a_records].empty? && result[:cname_records].empty?
      issues << {
        severity: SEVERITY_WARNING,
        code: "no_a_records",
        title: "No A Records",
        message: "No A records found. The domain won't resolve to an IP address.",
        recommendation: "Add an A record pointing to your web server's IP address."
      }
    end

    # Check for IPv6 support
    if result[:aaaa_records].empty? && result[:a_records].present?
      issues << {
        severity: SEVERITY_INFO,
        code: "no_ipv6",
        title: "No IPv6 Support",
        message: "No AAAA records found. The domain doesn't support IPv6.",
        recommendation: "Consider adding AAAA records for IPv6 connectivity."
      }
    end

    # Check for missing MX records
    if result[:mx_records].empty?
      issues << {
        severity: SEVERITY_WARNING,
        code: "no_mx_records",
        title: "No MX Records",
        message: "No MX records found. The domain cannot receive email.",
        recommendation: "Add MX records if email service is needed for this domain."
      }
    end

    # Check for missing NS records
    if result[:ns_records].empty?
      issues << {
        severity: SEVERITY_WARNING,
        code: "no_ns_records",
        title: "No NS Records",
        message: "No authoritative nameservers found in DNS.",
        recommendation: "Verify nameserver configuration with your DNS provider."
      }
    elsif result[:ns_records].length == 1
      issues << {
        severity: SEVERITY_WARNING,
        code: "single_ns",
        title: "Single Nameserver",
        message: "Only one nameserver found, which provides no redundancy.",
        recommendation: "Add at least one additional nameserver for reliability."
      }
    end

    # Check for resolver mismatches (DNS propagation issues)
    if resolver_results.length > 1
      a_records_by_resolver = resolver_results
        .select { |r| r[:success] }
        .map { |r| r[:a_records]&.sort || [] }
        .uniq

      if a_records_by_resolver.length > 1
        issues << {
          severity: SEVERITY_WARNING,
          code: "resolver_mismatch",
          title: "DNS Propagation Issue",
          message: "Different DNS resolvers returned different A records. This may indicate DNS propagation in progress.",
          recommendation: "Wait for DNS propagation to complete (up to 48 hours) or verify DNS configuration."
        }
      end

      mx_records_by_resolver = resolver_results
        .select { |r| r[:success] }
        .map { |r| (r[:mx_records] || []).map { |mx| mx[:host] }.sort }
        .uniq

      if mx_records_by_resolver.length > 1
        issues << {
          severity: SEVERITY_WARNING,
          code: "mx_resolver_mismatch",
          title: "MX Record Propagation Issue",
          message: "Different DNS resolvers returned different MX records.",
          recommendation: "Wait for DNS propagation to complete or verify MX configuration."
        }
      end
    end

    # Check for partial resolver failures
    failed_resolvers = resolver_results.select { |r| !r[:success] }.map { |r| r[:resolver] }
    if failed_resolvers.any? && resolver_results.any? { |r| r[:success] }
      issues << {
        severity: SEVERITY_INFO,
        code: "partial_resolver_failure",
        title: "Some Resolvers Failed",
        message: "DNS queries failed on: #{failed_resolvers.join(', ')}.",
        recommendation: "This may be a temporary network issue. Try again later."
      }
    end

    issues
  end

  private

  def check_with_resolver(resolver_name, resolver_address)
    result = {
      resolver: resolver_name,
      success: false,
      a_records: [],
      aaaa_records: [],
      mx_records: [],
      cname_records: [],
      ns_records: [],
      txt_records: [],
      error: nil,
      nxdomain: false
    }

    begin
      resolver = Dnsruby::Resolver.new(
        nameserver: resolver_address,
        timeout: TIMEOUT
      )

      # Query A records
      begin
        a_response = resolver.query(@domain, Dnsruby::Types::A)
        result[:a_records] = a_response.answer
          .select { |r| r.type == Dnsruby::Types::A }
          .map(&:address).map(&:to_s)
      rescue Dnsruby::NXDomain
        result[:nxdomain] = true
        result[:error] = "Domain does not exist (NXDomain)"
      rescue StandardError => e
        result[:error] = "A record query failed: #{e.message}" unless result[:error]
      end

      # Skip other queries if NXDOMAIN
      unless result[:nxdomain]
        # Query AAAA records (IPv6)
        begin
          aaaa_response = resolver.query(@domain, Dnsruby::Types::AAAA)
          result[:aaaa_records] = aaaa_response.answer
            .select { |r| r.type == Dnsruby::Types::AAAA }
            .map(&:address).map(&:to_s)
        rescue Dnsruby::NXDomain
          # No AAAA records
        rescue StandardError
          # Ignore AAAA errors, not critical
        end

        # Query MX records
        begin
          mx_response = resolver.query(@domain, Dnsruby::Types::MX)
          result[:mx_records] = mx_response.answer
            .select { |r| r.type == Dnsruby::Types::MX }
            .map { |r| { priority: r.preference, host: r.exchange.to_s } }
        rescue Dnsruby::NXDomain
          # No MX records
        rescue StandardError => e
          result[:error] = "MX record query failed: #{e.message}" unless result[:error]
        end

        # Query CNAME records
        begin
          cname_response = resolver.query(@domain, Dnsruby::Types::CNAME)
          result[:cname_records] = cname_response.answer
            .select { |r| r.type == Dnsruby::Types::CNAME }
            .map { |r| r.rdata.to_s }
        rescue Dnsruby::NXDomain
          # No CNAME records
        rescue StandardError
          # Ignore CNAME errors, not critical
        end

        # Query NS records
        begin
          ns_response = resolver.query(@domain, Dnsruby::Types::NS)
          result[:ns_records] = ns_response.answer
            .select { |r| r.type == Dnsruby::Types::NS }
            .map { |r| r.nsdname.to_s.downcase }
        rescue Dnsruby::NXDomain
          # No NS records
        rescue StandardError
          # Ignore NS errors, not critical
        end

        # Query TXT records (useful for SPF, DKIM, DMARC preview)
        begin
          txt_response = resolver.query(@domain, Dnsruby::Types::TXT)
          result[:txt_records] = txt_response.answer
            .select { |r| r.type == Dnsruby::Types::TXT }
            .map { |r| r.strings.join }
        rescue Dnsruby::NXDomain
          # No TXT records
        rescue StandardError
          # Ignore TXT errors, not critical
        end
      end

      result[:success] = !result[:nxdomain] || result[:error].nil?
    rescue Dnsruby::ResolvTimeout => e
      result[:error] = "DNS query timed out: #{e.message}"
    rescue StandardError => e
      result[:error] = "DNS resolution failed: #{e.message}"
    end

    result
  end
end

