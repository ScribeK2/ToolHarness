module Tools
  class HistoricalDns
    include ToolHarness::Tool

    def self.tool_name = "Historical DNS"
    def self.category  = :dns
    def self.description = "Shows how a domain's DNS records (A/AAAA/NS/MX/TXT) changed over time — " \
      "to pinpoint when it moved hosting, nameservers, or mail. Aggregates crt.sh (free), " \
      "VirusTotal (free key, id: virustotal), and WhoisFreaks (paid key, id: whoisfreaks — the only " \
      "source with NS/MX history). Add keys in the Credentials tool."
    def self.form_fields    = { domain: :text }
    def self.input_type     = :domain
    def self.cacheable?     = false              # self-managed conditional cache (below)
    def self.timeout        = 45
    def self.result_partial = "results/tools/historical_dns"

    CACHE_TTL     = 12.hours
    KEY_PROVIDERS = %w[whoisfreaks virustotal].freeze

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

      clean = providers.none? { |p| p[:status] == "error" }
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL) if clean && result.success?
      result
    end

    private

    def collect(domain, store)
      records = []
      subdomains = []
      providers = []
      ToolHarness::HistoricalDns::Provider.all.each do |klass|
        prov = klass.new
        unless prov.available?(store)
          providers << provider_row(klass, "no_key")
          next
        end
        begin
          key = klass.requires_key? ? store.secret_for(klass.id) : nil
          out = prov.fetch(domain, key: key)
          store.touch!(klass.id) if klass.requires_key?
          recs = Array(out[:records]); subs = Array(out[:subdomains])
          records.concat(recs); subdomains.concat(subs)
          status = (recs.empty? && subs.empty?) ? "no_data" : "ok"
          providers << provider_row(klass, status, count: recs.size + subs.size)
        rescue ToolHarness::HistoricalDns::ProviderError => e
          providers << provider_row(klass, "error", note: e.message)
        rescue StandardError => e
          providers << provider_row(klass, "error", note: "#{e.class}: #{e.message}")
        end
      end
      [records, dedupe_subdomains(subdomains), providers]
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
      any_ok   = providers.any? { |p| %w[ok no_data].include?(p[:status]) }

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
          "title" => "Only free subdomain history is active",
          "message" => "No API keys configured, so only crt.sh (subdomain history) ran.",
          "recommendation" => "Add a WhoisFreaks key (id: whoisfreaks) for full A/NS/MX history, " \
            "or a VirusTotal key (id: virustotal) for A-record history, in the Credentials tool." }
      end
      providers.select { |p| p[:status] == "error" }.each do |p|
        issues << { "severity" => "warning", "code" => "provider_failed",
          "title" => "#{p[:name]} lookup failed",
          "message" => p[:note].to_s,
          "recommendation" => "Showing data from the other sources." }
      end
      issues
    end

    def build_summary(domain, agg, providers)
      sources = providers.select { |p| p[:status] == "ok" }.map { |p| p[:name] }
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
