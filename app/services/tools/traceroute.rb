require "open3"
require "ipaddr"
require "timeout"

module Tools
  class Traceroute
    # AppImage builds cannot carry CAP_NET_RAW or rely on the host's
    # net.ipv4.ping_group_range. Until we ship a pure-userspace traceroute,
    # this tool is feature-flagged off. Set TOOLHARNESS_TRACEROUTE_ENABLED=1
    # to re-enable (development on a host with `traceroute` installed).
    include ToolHarness::Tool if ENV["TOOLHARNESS_TRACEROUTE_ENABLED"] == "1"

    MAX_HOPS         = 30
    WAIT_PER_PROBE_S = 1
    WALL_TIMEOUT_S   = 30
    MAX_OUTPUT_BYTES = 32_768

    def self.tool_name = "Traceroute"
    def self.category = :diagnostics
    def self.description = "Traces the network path to a host (up to #{MAX_HOPS} hops). Uses `traceroute` if available, otherwise falls back to `tracepath`. Safe shell-out via Open3 with strict input validation and a #{WALL_TIMEOUT_S}s wall-clock cap."
    def self.form_fields = { domain: :text }
    def self.input_type = :host
    def self.cacheable? = false
    def self.timeout = WALL_TIMEOUT_S + 5

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

      binary = pick_binary
      unless binary
        return ToolHarness::Result.new(
          success: false,
          tool: self.class.tool_name,
          error: "Neither 'traceroute' nor 'tracepath' is installed.",
          summary: "No trace command available"
        )
      end

      cmd = case binary
            when "traceroute" then ["traceroute", "-m", MAX_HOPS.to_s, "-w", WAIT_PER_PROBE_S.to_s, target]
            when "tracepath"  then ["tracepath", "-m", MAX_HOPS.to_s, target]
            end

      stdout, stderr, status, timed_out = run_with_timeout(cmd, WALL_TIMEOUT_S)

      if stdout.nil?
        return ToolHarness::Result.new(
          success: false,
          tool: self.class.tool_name,
          error: stderr.presence || "Traceroute failed to execute",
          summary: "Trace execution failed"
        )
      end

      hops    = parse(stdout, binary)
      reached = hops.any? && !hops.last[:timeout]

      issues = []
      if hops.empty?
        issues << {
          severity: "critical", code: "no_hops",
          title: "No hops parsed",
          message: "#{binary} produced no parseable hops (exit=#{status}, timed_out=#{timed_out}).",
          recommendation: "Verify the target resolves and #{binary} works from a shell."
        }
      elsif !reached && hops.size >= MAX_HOPS
        issues << {
          severity: "warning", code: "max_hops_exceeded",
          title: "Target not reached within #{MAX_HOPS} hops",
          message: "The trace stopped at the hop limit without responding from the destination.",
          recommendation: "Path may be longer than #{MAX_HOPS} hops, or intermediate routers are silently dropping probes."
        }
      elsif timed_out
        issues << {
          severity: "warning", code: "trace_timed_out",
          title: "Trace timed out",
          message: "Wall-clock timeout (#{WALL_TIMEOUT_S}s) hit before the trace completed; results are partial.",
          recommendation: "Slow paths may need a longer timeout; the partial trace shows hops reached so far."
        }
      end

      ToolHarness::Result.new(
        success: hops.any?,
        tool: self.class.tool_name,
        data: {
          target:     target,
          binary:     binary,
          hops:       hops,
          hop_count:  hops.size,
          reached:    reached,
          timed_out:  timed_out,
          raw_output: stdout.byteslice(0, MAX_OUTPUT_BYTES)
        },
        issues: issues,
        summary: build_summary(target, hops, reached, timed_out)
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

    def pick_binary
      %w[traceroute tracepath].find { |c| command_available?(c) }
    end

    def command_available?(cmd)
      system("which", cmd, out: File::NULL, err: File::NULL)
    end

    # Spawns reader threads so partial output is preserved when the wall-clock
    # timeout kills the process mid-trace. Without this, a slow tracepath that
    # times out at hop 12 would return zero hops.
    def run_with_timeout(cmd, timeout_s)
      Open3.popen3(*cmd) do |stdin, stdout_io, stderr_io, thread|
        stdin.close
        out = String.new
        err = String.new
        timed_out = false

        out_reader = Thread.new { drain_into(stdout_io, out) }
        err_reader = Thread.new { drain_into(stderr_io, err) }

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_s
        until thread.join(0.1)
          next unless Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          timed_out = true
          Process.kill("TERM", thread.pid) rescue nil
          sleep 0.3
          Process.kill("KILL", thread.pid) rescue nil
          thread.join
          break
        end

        out_reader.join(1)
        err_reader.join(1)

        [out, err, thread.value&.exitstatus, timed_out]
      end
    rescue Errno::ENOENT
      [nil, "#{cmd.first} command not available", nil, false]
    end

    def drain_into(io, buffer)
      while (chunk = io.read(4096))
        buffer << chunk
      end
    rescue StandardError
      # pipe closed by kill — whatever we have already in buffer is what we keep
    end

    def parse(out, binary)
      binary == "tracepath" ? parse_tracepath(out) : parse_traceroute(out)
    end

    def parse_traceroute(out)
      hops = []
      out.each_line do |line|
        next unless (m = line.match(/^\s*(\d+)\s+(.*?)$/))
        hop_num = m[1].to_i
        rest    = m[2].rstrip

        if rest.match?(/^\*+\s*\*?\s*\*?$/)
          hops << { hop: hop_num, hostname: nil, ip: nil, rtt_ms: [], timeout: true }
          next
        end

        hostname = nil
        ip       = nil
        if (h = rest.match(/^([^\s(]+)\s+\(([\d.:a-fA-F]+)\)/))
          hostname = h[1]
          ip       = h[2]
        elsif (h = rest.match(/^([\d.:a-fA-F]+)\s/))
          ip = h[1]
        end

        rtts = rest.scan(/([\d.]+)\s+ms/).flatten.map(&:to_f)
        hops << { hop: hop_num, hostname: hostname, ip: ip, rtt_ms: rtts, timeout: rtts.empty? }
      end
      hops
    end

    # tracepath emits one line per probe (often multiple probes per hop).
    # Coalesce by hop number, collecting RTTs as we go.
    def parse_tracepath(out)
      hops = {}
      out.each_line do |line|
        next unless (m = line.match(/^\s*(\d+)\??:\s+(.*?)$/))
        hop_num = m[1].to_i
        rest    = m[2].strip

        if rest.include?("no reply") || rest.match?(/\Apmtu\b/) || rest.match?(/\A\[LOCALHOST\]/)
          hops[hop_num] ||= { hop: hop_num, hostname: nil, ip: nil, rtt_ms: [], timeout: true }
          next
        end

        # Pattern: "<host or ip> [<rtt>ms] [asymm N]"
        if (mm = rest.match(/^(\S+)\s+([\d.]+)ms/))
          host = mm[1]
          rtt  = mm[2].to_f
          hop  = hops[hop_num] ||= { hop: hop_num, hostname: nil, ip: nil, rtt_ms: [], timeout: false }

          if valid_ip?(host)
            hop[:ip] ||= host
          else
            hop[:hostname] ||= host
          end
          hop[:rtt_ms] << rtt
          hop[:timeout] = false
        end
      end
      hops.values.sort_by { |h| h[:hop] }
    end

    def build_summary(target, hops, reached, timed_out)
      return "Trace returned no hops." if hops.empty?

      last     = hops.last
      last_avg = last[:rtt_ms].any? ? "#{(last[:rtt_ms].sum / last[:rtt_ms].size).round(1)}ms" : "timeout"
      verb     = reached ? "Reached" : "Stopped at"
      where    = last[:hostname] || last[:ip] || "hop #{last[:hop]}"
      suffix   = timed_out ? " (timed out)" : ""

      "#{verb} #{where} in #{hops.size} hops (last #{last_avg})#{suffix}."
    end
  end
end
