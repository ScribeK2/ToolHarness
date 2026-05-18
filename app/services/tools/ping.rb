require "socket"
require "ipaddr"

module Tools
  class Ping
    include ToolHarness::Tool

    PACKET_COUNT      = 4
    PACKET_TIMEOUT_S  = 2
    PROBE_PORTS       = [443, 80].freeze   # try 443 first; fall back to 80
    MAX_OUTPUT_BYTES  = 16_384

    def self.tool_name   = "Ping"
    def self.category    = :diagnostics
    def self.description = "Measures TCP reachability and round-trip time to a host by opening #{PACKET_COUNT} TCP connections (port 443 with port 80 fallback). No ICMP, no host ping binary, no elevated privileges required."
    def self.form_fields = { domain: :text }
    def self.input_type  = :host
    def self.cacheable?  = false
    def self.timeout     = 15

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

      probes = []
      port = nil
      PROBE_PORTS.each do |candidate|
        probes = run_probes(target, candidate)
        if probes.any? { |p| p[:rtt_ms] }
          port = candidate
          break
        end
      end
      port ||= PROBE_PORTS.first

      received = probes.count { |p| p[:rtt_ms] }
      sent     = probes.size
      loss     = sent.zero? ? 100.0 : ((sent - received).to_f / sent * 100).round(1)
      rtts     = probes.map { |p| p[:rtt_ms] }.compact
      rtt_stats = if rtts.any?
        { min: rtts.min.round(2), avg: (rtts.sum / rtts.size).round(2), max: rtts.max.round(2) }
      else
        { min: nil, avg: nil, max: nil }
      end

      reachable = received.positive?
      issues = []
      if !reachable
        issues << {
          severity: "critical",
          code: "host_unreachable",
          title: "Host did not accept TCP connections",
          message: "All #{sent} TCP probes to port #{port} failed.",
          recommendation: "Verify the host is up and ports 443/80 are not blocked by a firewall."
        }
      elsif loss > 0
        issues << {
          severity: "warning",
          code: "packet_loss",
          title: "Connection loss detected",
          message: "#{loss}% of TCP probes failed (#{received}/#{sent} succeeded) on port #{port}.",
          recommendation: "Investigate network reliability between this host and the target."
        }
      end

      data = {
        target:       target,
        port:         port,
        method:       "tcp-connect",
        sent:         sent,
        received:     received,
        loss_percent: loss,
        rtt:          rtt_stats,
        raw_output:   build_raw_output(target, port, probes).byteslice(0, MAX_OUTPUT_BYTES)
      }

      ToolHarness::Result.new(
        success: reachable,
        tool: self.class.tool_name,
        data: data,
        issues: issues,
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

    def run_probes(host, port)
      Array.new(PACKET_COUNT) { single_probe(host, port) }
    end

    def single_probe(host, port)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      socket = Socket.tcp(host, port, connect_timeout: PACKET_TIMEOUT_S)
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
      socket.close
      { port: port, rtt_ms: elapsed_ms.round(2) }
    rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError
      { port: port, rtt_ms: nil }
    rescue StandardError
      { port: port, rtt_ms: nil }
    end

    def build_raw_output(target, port, probes)
      lines = ["TCP-connect probe to #{target}:#{port}"]
      probes.each_with_index do |p, i|
        if p[:rtt_ms]
          lines << "probe #{i + 1}: connected in #{p[:rtt_ms]} ms"
        else
          lines << "probe #{i + 1}: failed"
        end
      end
      lines.join("\n")
    end

    def build_summary(d)
      received = d[:received]
      if received.positive?
        avg = d[:rtt][:avg]
        base = "#{received}/#{d[:sent]} TCP probes succeeded on port #{d[:port]}"
        base += ", avg #{avg}ms RTT" if avg
        base += " (#{d[:loss_percent]}% loss)" if d[:loss_percent] > 0
        "#{base}."
      else
        "All #{d[:sent]} TCP probes failed — host unreachable on ports #{PROBE_PORTS.join('/')}."
      end
    end
  end
end
