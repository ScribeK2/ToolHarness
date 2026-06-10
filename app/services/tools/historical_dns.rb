module Tools
  class HistoricalDns
    include ToolHarness::Tool

    def self.tool_name = "Historical DNS"
    def self.category  = :dns
    def self.description = "Shows how a domain's DNS records (A/AAAA/NS/MX/TXT) changed over time — " \
      "to pinpoint when it moved hosting, nameservers, or mail. Works with no API keys: " \
      "mnemonic (free A/AAAA/CNAME history), a live DNS lookup (current NS/MX/SOA), and crt.sh " \
      "(subdomain history). Optional keys add depth: VirusTotal (free key, id: virustotal — more " \
      "A-record history) and WhoisFreaks (paid key, id: whoisfreaks — full NS/MX history). " \
      "Add keys in the Credentials tool."
    def self.form_fields    = { domain: :text }
    def self.input_type     = :domain
    def self.cacheable?     = false              # self-managed conditional cache (below)
    def self.timeout        = 45
    def self.result_partial = "results/tools/historical_dns"

    CACHE_TTL        = 12.hours
    KEY_PROVIDERS    = %w[whoisfreaks virustotal].freeze
    COLLECT_DEADLINE = 14 # seconds — hard cap on the concurrent provider phase

    def execute(params)
      domain = params[:domain].to_s.strip.downcase
      return blank_result if domain.empty?

      cache_key = "toolharness:historical_dns:#{domain}"
      if (hit = Rails.cache.read(cache_key))
        hit.cached = true
        return hit
      end

      store = ToolHarness::CredentialStore.new
      records, subdomains, providers = collect(domain, store)
      agg    = ToolHarness::HistoricalDns::Aggregator.call(records)
      result = build_result(domain, agg, subdomains, providers)

      # Don't cache a degraded result: an errored provider, or a rate-limited partial
      # (so adding a paid key + re-running can fetch the full set).
      clean = providers.none? { |p| %w[error partial].include?(p[:status]) }
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL) if clean && result.success?
      result
    end

    private

    # Providers are independent and I/O-bound (crt.sh is slow), so fan them out concurrently:
    # the run is bounded by the slowest single provider, not the sum, and capped overall by
    # COLLECT_DEADLINE so a hung crt.sh can't dominate. Credential reads/writes stay on the
    # main thread (the store persists to a file) — only #fetch runs in threads, each wrapped
    # in the Rails executor so autoloading/reloading is thread-safe and actually parallel.
    def collect(domain, store)
      plan = ToolHarness::HistoricalDns::Provider.all.map do |klass|
        prov      = klass.new
        available = prov.available?(store)
        key       = (available && klass.requires_key?) ? store.secret_for(klass.id) : nil
        { klass: klass, prov: prov, available: available, key: key }
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      threads = plan.map do |p|
        next nil unless p[:available]
        Thread.new do
          Rails.application.executor.wrap do
            out = p[:prov].fetch(domain, key: p[:key])
            { records: Array(out[:records]), subdomains: Array(out[:subdomains]), partial: out[:partial] }
          end
        rescue ToolHarness::HistoricalDns::ProviderError => e
          { error: e.message }
        rescue StandardError => e
          { error: "#{e.class}: #{e.message}" }
        end
      end

      # Join under a shared deadline: a straggler past COLLECT_DEADLINE is abandoned (its
      # thread self-terminates on its own HTTP read timeout) and reported as a timeout error.
      outcomes = plan.each_index.map do |i|
        t = threads[i]
        next nil unless t
        remaining = COLLECT_DEADLINE - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        if t.join([remaining, 0].max)
          t.value
        else
          { error: "#{plan[i][:klass].display_name} timed out after #{COLLECT_DEADLINE}s" }
        end
      end

      records    = []
      subdomains = []
      providers  = []
      used_keys  = []
      plan.each_with_index do |p, i|
        klass = p[:klass]
        unless p[:available]
          providers << provider_row(klass, "no_key")
          next
        end
        res = outcomes[i]
        if res[:error]
          providers << provider_row(klass, "error", note: res[:error])
          next
        end
        recs = res[:records]
        subs = res[:subdomains]
        records.concat(recs)
        subdomains.concat(subs)
        used_keys << klass.id if klass.requires_key?
        if res[:partial]
          providers << provider_row(klass, "partial", note: partial_note(klass, res[:partial]), count: recs.size + subs.size)
        else
          status = (recs.empty? && subs.empty?) ? "no_data" : "ok"
          providers << provider_row(klass, status, count: recs.size + subs.size)
        end
      end

      used_keys.each { |id| store.touch!(id) }
      [records, dedupe_subdomains(subdomains), providers]
    end

    def partial_note(klass, partial)
      fetched = Array(partial[:fetched]).map { |t| t.to_s.upcase }
      skipped = Array(partial[:skipped]).map { |t| t.to_s.upcase }
      "Fetched #{fetched.join('/')} only — rate-limited after the first request " \
        "(#{klass.display_name} free tier is ~1 req/min), so #{skipped.join('/')} were skipped."
    end

    def provider_row(klass, status, note: nil, count: 0)
      { id: klass.id, name: klass.display_name, status: status, note: note, record_count: count }
    end

    def dedupe_subdomains(subs)
      acc = {}
      subs.each do |s|
        e = (acc[s[:name]] ||= { name: s[:name], first_seen: s[:first_seen], last_seen: s[:last_seen] })
        e[:first_seen] = [e[:first_seen], s[:first_seen]].compact.min
        e[:last_seen]  = [e[:last_seen],  s[:last_seen]].compact.max
      end
      acc.values.sort_by { |h| h[:name] }
    end

    def build_result(domain, agg, subdomains, providers)
      data = {
        domain:     domain,
        providers:  providers,
        timeline:   serialize_timeline(agg[:timeline]),
        changes:    agg[:changes].map { |c| c.merge(type: c[:type].to_s) },
        subdomains: subdomains.map { |s| { name: s[:name], first_seen: ym(s[:first_seen]), last_seen: ym(s[:last_seen]) } }
      }
      issues   = build_issues(providers)
      any_data = agg[:timeline].any? || subdomains.any?
      any_ok   = providers.any? { |p| %w[ok no_data partial].include?(p[:status]) }

      if any_data || any_ok
        ToolHarness::Result.new(success: true, tool: self.class.tool_name, data: data,
          issues: issues, summary: build_summary(domain, agg, providers))
      else
        notes = providers.map { |p| p[:note] }.compact.join("; ")
        ToolHarness::Result.new(success: false, tool: self.class.tool_name, data: data, issues: issues,
          error: notes.presence || "No historical DNS data available.",
          summary: "No historical DNS data for #{domain}.")
      end
    end

    def serialize_timeline(timeline)
      timeline.each_with_object({}) do |(type, recs), h|
        h[type.to_s] = recs.map do |m|
          { value: m[:value], first_seen: ym(m[:first_seen]), last_seen: ym(m[:last_seen]),
            current: m[:current], sources: m[:sources] }
        end
      end
    end

    def ym(date) = date&.strftime("%Y-%m")

    def build_issues(providers)
      issues = []
      if KEY_PROVIDERS.all? { |id| providers.find { |p| p[:id] == id }&.dig(:status) == "no_key" }
        issues << { "severity" => "info", "code" => "providers_limited",
          "title" => "Running on free sources only",
          "message" => "No API keys configured. Free sources cover A/AAAA/CNAME history (mnemonic), " \
            "the current NS/MX/SOA (live DNS), and subdomain history (crt.sh) — but NS/MX history needs a key.",
          "recommendation" => "Add a WhoisFreaks key (id: whoisfreaks) for full NS/MX history, " \
            "or a VirusTotal key (id: virustotal) for more A-record history, in the Credentials tool." }
      end
      providers.select { |p| p[:status] == "error" }.each do |p|
        issues << { "severity" => "warning", "code" => "provider_failed",
          "title" => "#{p[:name]} lookup failed",
          "message" => p[:note].to_s,
          "recommendation" => "Showing data from the other sources." }
      end
      providers.select { |p| p[:status] == "partial" }.each do |p|
        issues << { "severity" => "warning", "code" => "provider_partial",
          "title" => "#{p[:name]} returned partial history",
          "message" => p[:note].to_s,
          "recommendation" => "Add a paid #{p[:name]} plan for full multi-type history in one pass, " \
            "or re-run for more types. (This result is not cached.)" }
      end
      issues
    end

    def build_summary(domain, agg, providers)
      sources = providers.select { |p| %w[ok partial].include?(p[:status]) }
                         .map { |p| p[:status] == "partial" ? "#{p[:name]} (partial)" : p[:name] }
      parts   = agg[:changes].group_by { |c| c[:type] }.map { |type, cs| "#{type.to_s.upcase} changed ~#{cs.last[:approx_date]}" }
      head    = parts.any? ? parts.join("; ") : "no record changes detected"
      "#{domain} — #{head}. Sources: #{sources.any? ? sources.join(', ') : 'none'}."
    end

    def blank_result
      ToolHarness::Result.new(success: false, tool: self.class.tool_name,
        error: "Enter a domain.", summary: "No domain provided.")
    end
  end
end
