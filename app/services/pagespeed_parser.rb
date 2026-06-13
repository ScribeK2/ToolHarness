# Maps a PageSpeed Insights response into ToolHarness's result_data shape, plus
# derived issues and a one-line summary. Pure data transformation — no I/O.
class PagespeedParser
  METRIC_IDS = %w[
    first-contentful-paint speed-index largest-contentful-paint
    total-blocking-time cumulative-layout-shift interactive
  ].freeze

  VITALS = [
    %w[fcp First\ Contentful\ Paint first-contentful-paint],
    %w[si Speed\ Index speed-index],
    %w[lcp Largest\ Contentful\ Paint largest-contentful-paint],
    %w[tbt Total\ Blocking\ Time total-blocking-time],
    %w[cls Cumulative\ Layout\ Shift cumulative-layout-shift],
    %w[tti Time\ to\ Interactive interactive]
  ].freeze

  STRUCTURE_MODES = %w[binary numeric metricSavings].freeze

  RESOURCE_TYPES = {
    "Document" => "html", "Stylesheet" => "css", "Script" => "js",
    "Image" => "img", "Font" => "font", "Media" => "media",
    "Fetch" => "xhr", "XHR" => "xhr"
  }.freeze

  def self.parse(body, strategy:) = new(body, strategy:).call

  def initialize(body, strategy:)
    @body       = body || {}
    @strategy   = strategy.to_s
    @lighthouse = @body["lighthouseResult"] || {}
    @audits     = @lighthouse["audits"] || {}
  end

  def call
    recs = recommendations
    {
      data: {
        requested_url:  @lighthouse["requestedUrl"],
        final_url:      @lighthouse["finalDisplayedUrl"] || @lighthouse["finalUrl"],
        strategy:       @strategy,
        scores:         { performance: performance_score, structure: structure_score },
        metrics:        metrics,
        details:        { total_bytes: total_bytes, request_count: request_count,
                          fully_loaded_s: fully_loaded_s, field: field_data },
        recommendations: recs,
        waterfall:       waterfall
      },
      issues:  issues_from(recs),
      summary: summary
    }
  end

  private

  def performance_score
    s = @lighthouse.dig("categories", "performance", "score")
    s.nil? ? nil : (s * 100).round
  end

  def structure_score
    scored = @audits.reject { |id, _| METRIC_IDS.include?(id) }.values.select do |a|
      a["score"].is_a?(Numeric) && STRUCTURE_MODES.include?(a["scoreDisplayMode"])
    end
    return nil if scored.empty?
    (scored.sum { |a| a["score"] } / scored.size * 100).round
  end

  def metrics
    VITALS.map do |key, label, audit_id|
      a = @audits[audit_id] || {}
      { key: key, label: label, value: a["displayValue"].to_s, grade: grade_for(a["score"]) }
    end
  end

  def grade_for(score)
    return "info" if score.nil?
    if    score >= 0.9 then "ok"
    elsif score >= 0.5 then "warn"
    else                    "crit"
    end
  end

  def recommendations
    @audits.values.select { |a|
      a.dig("details", "type") == "opportunity" && a["score"].is_a?(Numeric) && a["score"] < 1
    }.sort_by { |a|
      -a.dig("details", "overallSavingsMs").to_f
    }.map { |a|
      { sev: rec_sev(a["score"]), title: a["title"].to_s, saving: saving_label(a) }
    }
  end

  def rec_sev(score)
    score < 0.5 ? "crit" : "warn"
  end

  def saving_label(a)
    d     = a["details"] || {}
    bytes = d["overallSavingsBytes"].to_i
    ms    = d["overallSavingsMs"].to_i
    if    bytes.positive? then "~#{human_size(bytes)}"
    elsif ms.positive?    then "~#{(ms / 1000.0).round(1)}s"
    else                       ""
    end
  end

  def issues_from(recs)
    sev_map = { "crit" => "critical", "warn" => "warning" }
    recs.select { |r| sev_map.key?(r[:sev]) }.map do |r|
      { "severity" => sev_map[r[:sev]], "code" => "page_speed_opportunity",
        "title" => r[:title],
        "message" => ["Estimated saving", r[:saving]].reject(&:blank?).join(" "),
        "recommendation" => r[:title] }
    end
  end

  def waterfall
    network_items.map.with_index(1) do |i, n|
      { n: n, url: i["url"].to_s, type: (RESOURCE_TYPES[i["resourceType"]] || "other"),
        bytes: i["transferSize"].to_i,
        start_ms: i["startTime"].to_f.round, end_ms: i["endTime"].to_f.round }
    end
  end

  def network_items
    @audits.dig("network-requests", "details", "items") || []
  end

  def total_bytes
    network_items.sum { |i| i["transferSize"].to_i }
  end

  def request_count
    network_items.size
  end

  def fully_loaded_s
    max_end = network_items.map { |i| i["endTime"].to_f }.max || 0.0
    (max_end / 1000.0).round(1)
  end

  def field_data
    le      = @body["loadingExperience"] || {}
    metrics = le["metrics"] || {}
    return { available: false } if metrics.empty?
    {
      available: true,
      lcp_ms:   metrics.dig("LARGEST_CONTENTFUL_PAINT_MS", "percentile"),
      inp_ms:   metrics.dig("INTERACTION_TO_NEXT_PAINT", "percentile"),
      cls:      metrics.dig("CUMULATIVE_LAYOUT_SHIFT_SCORE", "percentile").to_f / 100.0,
      category: le["overall_category"]
    }
  end

  def summary
    lcp = metrics.find { |m| m[:key] == "lcp" }&.dig(:value).presence || "—"
    "Perf #{performance_score} · LCP #{lcp} · #{request_count} requests · " \
      "#{human_size(total_bytes)} (#{@strategy})"
  end

  def human_size(bytes)
    kb = bytes / 1024.0
    kb >= 1024 ? "#{(kb / 1024).round(1)} MB" : "#{kb.round} KB"
  end
end
