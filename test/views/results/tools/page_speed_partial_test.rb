require "test_helper"

class PageSpeedPartialTest < ActionView::TestCase
  SAMPLE = {
    "requested_url" => "https://example.com/", "final_url" => "https://example.com/",
    "strategy" => "mobile",
    "scores" => { "performance" => 72, "structure" => 66 },
    "metrics" => [
      { "key" => "lcp", "label" => "Largest Contentful Paint", "value" => "3.1 s", "grade" => "warn" },
      { "key" => "cls", "label" => "Cumulative Layout Shift",  "value" => "0.04",  "grade" => "ok" }
    ],
    "details" => { "total_bytes" => 906_240, "request_count" => 5, "fully_loaded_s" => 1.4,
                   "field" => { "available" => true, "lcp_ms" => 2400, "inp_ms" => 180,
                                "cls" => 0.02, "category" => "FAST" } },
    "recommendations" => [
      { "sev" => "crit", "title" => "Eliminate render-blocking resources", "saving" => "~0.9s" }
    ],
    "waterfall" => [
      { "n" => 1, "url" => "https://example.com/", "type" => "html",
        "bytes" => 12_288, "start_ms" => 0, "end_ms" => 300 }
    ]
  }.freeze

  test "renders all five sections from result_data" do
    tool_run = Struct.new(:result_data).new(SAMPLE)
    render partial: "results/tools/page_speed", locals: { tool_run: tool_run }

    assert_match "PERFORMANCE", rendered
    assert_match "72", rendered
    assert_match "STRUCTURE", rendered
    assert_match "Largest Contentful Paint", rendered
    assert_match "WARN", rendered
    assert_match "Eliminate render-blocking resources", rendered
    assert_match "~0.9s", rendered
    assert_match(/WATERFALL/i, rendered)
    assert_match "FAST", rendered                 # CrUX field data
  end

  test "renders 'no field data' when CrUX is unavailable" do
    sample = SAMPLE.deep_dup
    sample["details"]["field"] = { "available" => false }
    tool_run = Struct.new(:result_data).new(sample)
    render partial: "results/tools/page_speed", locals: { tool_run: tool_run }
    assert_match(/no field data/i, rendered)
  end
end
