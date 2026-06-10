require "socket"
require "resolv"
require "ipaddr"
require "net/http"

module Tools
  class HostingDiagnostic
    include ToolHarness::Tool

    PORTS_TO_CHECK = {
      ftp:         21,
      ssh:         22,
      smtp:        25,
      http:        80,
      pop3:        110,
      imap:        143,
      https:       443,
      smtps:       465,
      submission:  587,
      imaps:       993,
      pop3s:       995,
      cpanel_ssl:  2083,
      whm_ssl:     2087,
      mysql:       3306,
      postgresql:  5432,
      redis:       6379,
      mongodb:     27017
    }.freeze
    PORT_TIMEOUT_S = 2
    DEPTHS = %w[full quick].freeze

    def self.tool_name = "Hosting Diagnostic"
    def self.category = :hosting
    def self.description = "Resolves the host and probes common service ports in parallel (SSH, HTTP, mail, cPanel/WHM, databases) with reverse DNS and the HTTPS banner — or, at quick depth, just measures TCP reachability and round-trip time (4 probes, port 443/80)."
    def self.form_fields = {
      domain: :text,
      depth: { type: :select, options: DEPTHS }
    }
    def self.input_type = :host
    def self.cacheable? = false
    def self.timeout = 30

    def execute(params)
      target = params[:domain].to_s.strip

      unless valid_target?(target)
        return ToolHarness::Result.new(
          success: false,
          tool: self.class.tool_name,
          error: "Invalid target: must be a domain name or IP address.",
          summary: "Invalid input"
        )
      end

      depth = params[:depth].presence || "full"
      return execute_quick(target) if depth == "quick"

      ip = valid_ip?(target) ? target : resolve_ip(target)
      unless ip
        return ToolHarness::Result.new(
          success: false,
          tool: self.class.tool_name,
          error: "Could not resolve #{target} to an IP address.",
          summary: "DNS resolution failed for #{target}"
        )
      end

      ports         = check_ports_parallel(ip)
      open_keys     = ports.select { |_, v| v[:open] }.keys
      reverse_dns   = reverse_lookup(ip)
      server_banner = valid_ip?(target) ? nil : fetch_server_banner(target)

      data = {
        target:        target,
        ip:            ip,
        reverse_dns:   reverse_dns,
        ports:         ports,
        open_ports:    open_keys,
        server_banner: server_banner
      }

      ToolHarness::Result.new(
        success: true,
        tool: self.class.tool_name,
        data: data,
        issues: build_issues(data),
        summary: build_summary(data)
      )
    end

    private

    def valid_target?(s)
      return false if s.empty? || s.size > 253
      return true if valid_ip?(s)
      s.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?)+\z/)
    end

    def valid_ip?(s)
      IPAddr.new(s) && true
    rescue IPAddr::InvalidAddressError
      false
    end

    def resolve_ip(domain)
      dns = ::DnsChecker.check(domain)
      dns[:a_records]&.first
    rescue StandardError
      nil
    end

    def reverse_lookup(ip)
      Resolv.getname(ip)
    rescue Resolv::ResolvError, Resolv::ResolvTimeout
      nil
    end

    def check_ports_parallel(host)
      threads = PORTS_TO_CHECK.map do |label, port|
        Thread.new do
          start  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          open   = port_open?(host, port)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          [label, { port: port, open: open, response_ms: (elapsed * 1000).round }]
        end
      end
      threads.map(&:value).to_h
    end

    def port_open?(host, port)
      Socket.tcp(host, port, connect_timeout: PORT_TIMEOUT_S) { true }
    rescue StandardError
      false
    end

    def fetch_server_banner(domain)
      uri = URI("https://#{domain}/")
      Net::HTTP.start(uri.host, uri.port,
                     use_ssl: true,
                     open_timeout: 3,
                     read_timeout: 5,
                     verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
        resp = http.head("/")
        {
          server:     resp["server"],
          powered_by: resp["x-powered-by"],
          status:     resp.code.to_i
        }
      end
    rescue StandardError
      nil
    end

    def build_issues(data)
      issues = []
      open   = data[:open_ports]

      if open.empty?
        issues << {
          severity: "warning",
          code: "no_ports_open",
          title: "No common ports responding",
          message: "None of #{PORTS_TO_CHECK.size} probed ports accepted connections.",
          recommendation: "Verify the host is up and not blocked by a firewall."
        }
      end

      if (open & [:cpanel_ssl, :whm_ssl]).any?
        issues << {
          severity: "info",
          code: "control_panel_detected",
          title: "Control panel detected",
          message: "#{(open & [:cpanel_ssl, :whm_ssl]).map { |k| "#{k} (#{PORTS_TO_CHECK[k]})" }.join(', ')} responding — likely cPanel/WHM.",
          recommendation: "Consider wiring the cPanel/WHM API for richer diagnostics on this host."
        }
      end

      if (open & [:mysql, :postgresql, :redis, :mongodb]).any?
        db_ports = (open & [:mysql, :postgresql, :redis, :mongodb])
        issues << {
          severity: "warning",
          code: "database_port_exposed",
          title: "Database port reachable",
          message: "Database services responding to public connection attempts: #{db_ports.join(', ')}.",
          recommendation: "Database ports should normally be firewalled to internal traffic only. Verify access rules."
        }
      end

      issues
    end

    def build_summary(data)
      open    = data[:open_ports]
      reverse = data[:reverse_dns]

      base = "#{data[:target]} → #{data[:ip]}"
      base += " (#{reverse})" if reverse && reverse != data[:target]
      if open.any?
        sample = open.first(5).map { |k| "#{k}:#{PORTS_TO_CHECK[k]}" }.join(", ")
        more   = open.size > 5 ? ", …" : ""
        base += ". #{open.size} of #{PORTS_TO_CHECK.size} ports open (#{sample}#{more})"
      else
        base += ". No probed ports open"
      end
      "#{base}."
    end

    def execute_quick(target)
      probe = ::TcpPingProbe.check(target)
      data  = probe[:data].merge(depth: "quick")

      ToolHarness::Result.new(
        success: probe[:reachable],
        tool: self.class.tool_name,
        data: data,
        issues: probe[:issues],
        summary: quick_summary(data)
      )
    end

    def quick_summary(d)
      received = d[:received]
      if received.positive?
        avg = d[:rtt][:avg]
        base = "#{received}/#{d[:sent]} TCP probes succeeded on port #{d[:port]}"
        base += ", avg #{avg}ms RTT" if avg
        base += " (#{d[:loss_percent]}% loss)" if d[:loss_percent] > 0
        "#{base}."
      else
        "All #{d[:sent]} TCP probes failed — host unreachable on ports #{TcpPingProbe::PROBE_PORTS.join('/')}."
      end
    end
  end
end
