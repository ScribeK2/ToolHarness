require "socket"
require "ipaddr"

# TCP-connect reachability probe (no ICMP, no ping binary, no privileges).
# Quick-depth engine for Tools::HostingDiagnostic; formerly Tools::Ping.
# Returns { valid:, reachable:, data:, issues: }.
class TcpPingProbe
  PACKET_COUNT      = 4
  PACKET_TIMEOUT_S  = 2
  PROBE_PORTS       = [ 443, 80 ].freeze # try 443 first; fall back to 80
  MAX_OUTPUT_BYTES  = 16_384

  def self.check(target) = new(target).check

  def initialize(target)
    @target = target.to_s.strip
  end

  def check
    return { valid: false, reachable: false, data: {}, issues: [] } unless valid_target?(@target)

    probes = []
    port = nil
    PROBE_PORTS.each do |candidate|
      probes = run_probes(@target, candidate)
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
      target:       @target,
      port:         port,
      method:       "tcp-connect",
      sent:         sent,
      received:     received,
      loss_percent: loss,
      rtt:          rtt_stats,
      raw_output:   build_raw_output(@target, port, probes).byteslice(0, MAX_OUTPUT_BYTES)
    }

    { valid: true, reachable: reachable, data: data, issues: issues }
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
  rescue StandardError
    { port: port, rtt_ms: nil }
  end

  def build_raw_output(target, port, probes)
    lines = [ "TCP-connect probe to #{target}:#{port}" ]
    probes.each_with_index do |p, i|
      if p[:rtt_ms]
        lines << "probe #{i + 1}: connected in #{p[:rtt_ms]} ms"
      else
        lines << "probe #{i + 1}: failed"
      end
    end
    lines.join("\n")
  end
end
