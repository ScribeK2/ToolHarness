# Maps a PageSpeed Insights response into ToolHarness's result_data shape, plus
# derived issues and a one-line summary. Pure data transformation — no I/O.
class PagespeedParser
  METRIC_IDS = %w[
    first-contentful-paint speed-index largest-contentful-paint
    total-blocking-time cumulative-layout-shift interactive
  ].freeze

  VITALS = [
    %w[fcp First\ Contentful\ Paint   first-contentful-paint],
    %w[si  Speed\ Index               speed-index],
    %w[lcp Largest\ Contentful\ Paint largest-contentful-paint],
    %w[tbt Total\ Blocking\ Time      total-blocking-time],
    %w[cls Cumulative\ Layout\ Shift  cumulative-layout-shift],
    %w[tti Time\ to\ Interactive      interactive]
  ].freeze

  STRUCTURE_MODES = %w[binary numeric metricSavings].freeze

  def self.parse(body, strategy:) = new(body, strategy:).call

  def initialize(body, strategy:)
    @body       = body || {}
    @strategy   = strategy.to_s
    @lighthouse = @body["lighthouseResult"] || {}
    @audits     = @lighthouse["audits"] || {}
  end

  def call
    {
      data: {
        requested_url: @lighthouse["requestedUrl"],
        final_url:     @lighthouse["finalDisplayedUrl"] || @lighthouse["finalUrl"],
        strategy:      @strategy,
        scores:        { performance: performance_score, structure: structure_score },
        metrics:       metrics,
        details:       { total_bytes: total_bytes, request_count: request_count,
                         fully_loaded_s: fully_loaded_s, field: field_data }
      },
      issues:  [],   # populated in Task 3
      summary: nil   # populated in Task 3
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
end
