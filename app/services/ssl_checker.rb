require "net/http"
require "openssl"
require "socket"

class SslChecker
  TIMEOUT = 10.seconds

  # Issue severity levels
  SEVERITY_CRITICAL = "critical"
  SEVERITY_WARNING = "warning"
  SEVERITY_INFO = "info"

  # Supported TLS versions (in order of preference)
  TLS_VERSIONS = {
    "TLSv1.3" => OpenSSL::SSL::TLS1_3_VERSION,
    "TLSv1.2" => OpenSSL::SSL::TLS1_2_VERSION
  }.freeze

  # Deprecated TLS versions to check for
  DEPRECATED_TLS = {
    "TLSv1.1" => OpenSSL::SSL::TLS1_1_VERSION,
    "TLSv1.0" => OpenSSL::SSL::TLS1_VERSION
  }.freeze

  def self.check(domain, port: 443)
    new(domain, port).check
  end

  def initialize(domain, port = 443)
    @domain = domain.to_s.strip.downcase
    @port = port
  end

  def check
    cache_key = "ssl:#{@domain}:#{@port}"
    cached_result = Rails.cache.read(cache_key)
    return cached_result if cached_result

    result = {
      success: false,
      domain: @domain,
      port: @port,
      certificate: nil,
      chain: [],
      supported_protocols: [],
      deprecated_protocols: [],
      issues: [],
      error: nil,
      checked_at: Time.current.iso8601
    }

    begin
      # Get certificate and chain
      cert_info = fetch_certificate
      result[:certificate] = cert_info[:certificate]
      result[:chain] = cert_info[:chain]
      result[:success] = true

      # Check supported TLS versions
      result[:supported_protocols] = check_tls_versions
      result[:deprecated_protocols] = check_deprecated_tls

      # Detect issues
      result[:issues] = detect_issues(result)
    rescue OpenSSL::SSL::SSLError => e
      result[:error] = "SSL error: #{e.message}"
      result[:issues] = [{
        severity: SEVERITY_CRITICAL,
        code: "ssl_error",
        title: "SSL Connection Failed",
        message: "Could not establish SSL connection: #{e.message}",
        recommendation: "Verify SSL certificate is properly installed and not expired."
      }]
    rescue Errno::ECONNREFUSED
      result[:error] = "Connection refused on port #{@port}"
      result[:issues] = [{
        severity: SEVERITY_CRITICAL,
        code: "connection_refused",
        title: "Connection Refused",
        message: "Port #{@port} is not accepting connections.",
        recommendation: "Verify the server is running and SSL is enabled."
      }]
    rescue Errno::ETIMEDOUT, Net::OpenTimeout
      result[:error] = "Connection timed out"
      result[:issues] = [{
        severity: SEVERITY_CRITICAL,
        code: "timeout",
        title: "Connection Timeout",
        message: "SSL connection timed out after #{TIMEOUT} seconds.",
        recommendation: "Check if the server is reachable and responding."
      }]
    rescue SocketError => e
      result[:error] = "DNS resolution failed: #{e.message}"
      result[:issues] = [{
        severity: SEVERITY_CRITICAL,
        code: "dns_error",
        title: "DNS Resolution Failed",
        message: "Could not resolve domain: #{e.message}",
        recommendation: "Verify the domain name is correct and DNS is configured."
      }]
    rescue StandardError => e
      result[:error] = "Unexpected error: #{e.message}"
    end

    # Cache successful results for 1 hour
    Rails.cache.write(cache_key, result, expires_in: 1.hour) if result[:success]

    result
  end

  private

  def fetch_certificate
    cert_info = { certificate: nil, chain: [] }

    tcp_client = TCPSocket.new(@domain, @port)
    tcp_client.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER
    ssl_context.cert_store = OpenSSL::X509::Store.new
    ssl_context.cert_store.set_default_paths

    ssl_client = OpenSSL::SSL::SSLSocket.new(tcp_client, ssl_context)
    ssl_client.hostname = @domain
    ssl_client.sync_close = true

    Timeout.timeout(TIMEOUT) do
      ssl_client.connect
    end

    cert = ssl_client.peer_cert
    chain = ssl_client.peer_cert_chain || []

    cert_info[:certificate] = parse_certificate(cert)
    cert_info[:chain] = chain.map { |c| parse_certificate(c) }

    ssl_client.close
    cert_info
  rescue => e
    tcp_client&.close
    raise e
  end

  def parse_certificate(cert)
    return nil unless cert

    # Extract subject alternative names
    san_extension = cert.extensions.find { |ext| ext.oid == "subjectAltName" }
    sans = []
    if san_extension
      sans = san_extension.value.split(", ").map { |s| s.gsub(/^DNS:/, "") }
    end

    {
      subject: cert.subject.to_s,
      issuer: cert.issuer.to_s,
      common_name: extract_cn(cert.subject),
      issuer_name: extract_cn(cert.issuer),
      organization: extract_org(cert.subject),
      issuer_organization: extract_org(cert.issuer),
      serial: cert.serial.to_s,
      not_before: cert.not_before.iso8601,
      not_after: cert.not_after.iso8601,
      days_until_expiry: ((cert.not_after - Time.now) / 86400).to_i,
      subject_alt_names: sans,
      signature_algorithm: cert.signature_algorithm,
      key_size: extract_key_size(cert),
      is_self_signed: cert.subject.to_s == cert.issuer.to_s,
      version: cert.version + 1  # X.509 version is 0-indexed
    }
  end

  def extract_cn(name)
    name.to_a.find { |attr| attr[0] == "CN" }&.dig(1)
  end

  def extract_org(name)
    name.to_a.find { |attr| attr[0] == "O" }&.dig(1)
  end

  def extract_key_size(cert)
    case cert.public_key
    when OpenSSL::PKey::RSA
      cert.public_key.n.num_bits
    when OpenSSL::PKey::EC
      cert.public_key.group.degree
    else
      nil
    end
  rescue
    nil
  end

  def check_tls_versions
    supported = []

    TLS_VERSIONS.each do |name, version|
      if tls_version_supported?(version)
        supported << name
      end
    end

    supported
  end

  def check_deprecated_tls
    deprecated = []

    DEPRECATED_TLS.each do |name, version|
      if tls_version_supported?(version)
        deprecated << name
      end
    end

    deprecated
  end

  def tls_version_supported?(version)
    tcp_client = TCPSocket.new(@domain, @port)
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.min_version = version
    ssl_context.max_version = version
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE

    ssl_client = OpenSSL::SSL::SSLSocket.new(tcp_client, ssl_context)
    ssl_client.hostname = @domain
    ssl_client.sync_close = true

    Timeout.timeout(5) do
      ssl_client.connect
    end

    ssl_client.close
    true
  rescue
    tcp_client&.close
    false
  end

  def detect_issues(result)
    issues = []
    cert = result[:certificate]

    return issues unless cert

    # Check expiration
    days_until_expiry = cert[:days_until_expiry]
    if days_until_expiry < 0
      issues << {
        severity: SEVERITY_CRITICAL,
        code: "cert_expired",
        title: "Certificate Expired",
        message: "Certificate expired #{days_until_expiry.abs} days ago.",
        recommendation: "Renew the SSL certificate immediately."
      }
    elsif days_until_expiry <= 7
      issues << {
        severity: SEVERITY_CRITICAL,
        code: "cert_expiring_soon",
        title: "Certificate Expiring Very Soon",
        message: "Certificate expires in #{days_until_expiry} days.",
        recommendation: "Renew the SSL certificate immediately."
      }
    elsif days_until_expiry <= 30
      issues << {
        severity: SEVERITY_WARNING,
        code: "cert_expiring",
        title: "Certificate Expiring Soon",
        message: "Certificate expires in #{days_until_expiry} days.",
        recommendation: "Schedule certificate renewal."
      }
    elsif days_until_expiry <= 90
      issues << {
        severity: SEVERITY_INFO,
        code: "cert_renewal_reminder",
        title: "Renewal Reminder",
        message: "Certificate expires in #{days_until_expiry} days.",
        recommendation: "Consider setting up auto-renewal if not already enabled."
      }
    end

    # Check self-signed
    if cert[:is_self_signed]
      issues << {
        severity: SEVERITY_WARNING,
        code: "self_signed",
        title: "Self-Signed Certificate",
        message: "The certificate is self-signed and won't be trusted by browsers.",
        recommendation: "Use a certificate from a trusted Certificate Authority."
      }
    end

    # Check domain match
    cn = cert[:common_name]&.downcase
    sans = cert[:subject_alt_names]&.map(&:downcase) || []
    all_names = ([cn] + sans).compact.uniq

    domain_matches = all_names.any? do |name|
      if name.start_with?("*.")
        # Wildcard match
        pattern = name.sub("*.", "")
        @domain == pattern || @domain.end_with?(".#{pattern}")
      else
        @domain == name
      end
    end

    unless domain_matches
      issues << {
        severity: SEVERITY_CRITICAL,
        code: "domain_mismatch",
        title: "Domain Mismatch",
        message: "Certificate is for #{all_names.first(3).join(', ')}#{all_names.length > 3 ? '...' : ''}, not #{@domain}.",
        recommendation: "Obtain a certificate that includes #{@domain}."
      }
    end

    # Check key size
    key_size = cert[:key_size]
    if key_size && key_size < 2048
      issues << {
        severity: SEVERITY_WARNING,
        code: "weak_key",
        title: "Weak Key Size",
        message: "Certificate uses a #{key_size}-bit key, which is considered weak.",
        recommendation: "Use at least 2048-bit RSA or 256-bit ECDSA keys."
      }
    end

    # Check deprecated TLS
    if result[:deprecated_protocols].any?
      issues << {
        severity: SEVERITY_WARNING,
        code: "deprecated_tls",
        title: "Deprecated TLS Versions",
        message: "Server supports deprecated protocols: #{result[:deprecated_protocols].join(', ')}.",
        recommendation: "Disable TLS 1.0 and TLS 1.1 for security."
      }
    end

    # Check if TLS 1.3 is supported
    unless result[:supported_protocols].include?("TLSv1.3")
      issues << {
        severity: SEVERITY_INFO,
        code: "no_tls_1_3",
        title: "TLS 1.3 Not Supported",
        message: "Server does not support TLS 1.3.",
        recommendation: "Enable TLS 1.3 for improved security and performance."
      }
    end

    # Check certificate chain
    if result[:chain].length <= 1
      issues << {
        severity: SEVERITY_INFO,
        code: "incomplete_chain",
        title: "Incomplete Certificate Chain",
        message: "Certificate chain may be incomplete (only #{result[:chain].length} certificate(s)).",
        recommendation: "Ensure intermediate certificates are properly configured."
      }
    end

    issues
  end
end
