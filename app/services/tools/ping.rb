require "open3"
require "ipaddr"

module Tools
  class Ping
    include ToolHarness::Tool

    PACKET_COUNT     = 4
    PACKET_TIMEOUT_S = 2
    MAX_OUTPUT_BYTES = 16_384

    def self.tool_name = "Ping"
    def self.category = :diagnostics
    def self.description = "Sends #{PACKET_COUNT} ICMP echo requests to a host and reports packet loss and round-trip times. Safe shell-out via Open3 with strict input validation."
    def self.form_fields = { domain: :text }
    def self.input_type = :host
    def self.cacheable? = false
    def self.timeout = 15

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

      stdout, stderr, status = run_command("ping", "-c", PACKET_COUNT.to_s, "-W", PACKET_TIMEOUT_S.to_s, target)

      if stdout.nil?
        return ToolHarness::Result.new(
          success: false,
          tool: self.class.tool_name,
          error: stderr.presence || "Ping failed to execute",
          summary: "Ping execution failed"
        )
      end

      parsed   = parse_ping(stdout, target)
      received = parsed[:received].to_i
      reachable = received.positive?

      issues = []
      if !reachable
        issues << {
          severity: "critical",
          code: "host_unreachable",
          title: "Host did not respond",
          message: "All #{parsed[:sent]} packets lost (exit status #{status}).",
          recommendation: "Verify the host is up and ICMP is not blocked by a firewall."
        }
      elsif parsed[:loss_percent].to_f > 0
        issues << {
          severity: "warning",
          code: "packet_loss",
          title: "Packet loss detected",
          message: "#{parsed[:loss_percent]}% packet loss (#{received}/#{parsed[:sent]} received).",
          recommendation: "Investigate network reliability between this host and the target."
        }
      end

      ToolHarness::Result.new(
        success: reachable,
        tool: self.class.tool_name,
        data: parsed.merge(raw_output: stdout.byteslice(0, MAX_OUTPUT_BYTES)),
        issues: issues,
        summary: build_summary(parsed)
      )
    end

    private

    def valid_target?(s)
      return false if s.empty? || s.size > 253
      return true if valid_ip?(s)
      # Domain pattern — alnum start/end, hyphens/dots inside, must contain at least one dot
      s.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?)+\z/)
    end

    def valid_ip?(s)
      IPAddr.new(s) && true
    rescue IPAddr::InvalidAddressError
      false
    end

    def run_command(*cmd)
      stdout, stderr, status = Open3.capture3(*cmd)
      [stdout, stderr, status.exitstatus]
    rescue Errno::ENOENT
      [nil, "ping command not available in this environment", nil]
    end

    def parse_ping(out, target)
      result = {
        target: target,
        sent: nil,
        received: nil,
        loss_percent: nil,
        rtt: { min: nil, avg: nil, max: nil }
      }

      # Linux ping summary line
      if (m = out.match(/(\d+)\s+packets?\s+transmitted,\s+(\d+)\s+(?:packets?\s+)?received,\s+([\d.]+)%\s+packet\s+loss/))
        result[:sent] = m[1].to_i
        result[:received] = m[2].to_i
        result[:loss_percent] = m[3].to_f
      end

      # rtt line (Linux) or round-trip (macOS/BSD)
      if (m = out.match(%r{(?:rtt|round-trip)\s+min/avg/max[^=]*=\s+([\d.]+)/([\d.]+)/([\d.]+)}))
        result[:rtt] = { min: m[1].to_f, avg: m[2].to_f, max: m[3].to_f }
      end

      result
    end

    def build_summary(p)
      received = p[:received].to_i
      if received.positive?
        avg = p[:rtt][:avg]
        base = "#{received}/#{p[:sent]} packets received"
        base += ", avg #{avg.round(1)}ms RTT" if avg
        base += " (#{p[:loss_percent]}% loss)" if p[:loss_percent].to_f.positive?
        "#{base}."
      else
        "All #{p[:sent] || PACKET_COUNT} packets lost — host unreachable."
      end
    end
  end
end
