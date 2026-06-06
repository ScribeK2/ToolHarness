require "test_helper"

class PagespeedParserTest < ActiveSupport::TestCase
  def parsed(strategy: "mobile")
    body = JSON.parse(file_fixture("pagespeed_example.json").read)
    PagespeedParser.parse(body, strategy: strategy)
  end

  test "performance score is the category score x100, rounded" do
    assert_equal 72, parsed[:data][:scores][:performance]
  end

  test "structure score is the mean of scored non-metric audits x100" do
    # scored non-metric audits: 0.40, 0.30, 0.60, 1.00, 1.00 -> mean 0.66 -> 66
    assert_equal 66, parsed[:data][:scores][:structure]
  end

  test "web vitals are the six metrics with values and graded" do
    metrics = parsed[:data][:metrics]
    assert_equal 6, metrics.size
    lcp = metrics.find { |m| m[:key] == "lcp" }
    assert_equal "Largest Contentful Paint", lcp[:label]
    assert_equal "3.1 s", lcp[:value]
    assert_equal "warn", lcp[:grade]                     # score 0.50 -> warn
    assert_equal "ok",   metrics.find { |m| m[:key] == "fcp" }[:grade]  # 0.90 -> ok
  end

  test "page details totals requests, bytes and fully-loaded time" do
    d = parsed[:data][:details]
    assert_equal 5, d[:request_count]
    assert_equal 906_240, d[:total_bytes]               # sum of transferSize
    assert_in_delta 1.4, d[:fully_loaded_s], 0.001      # max endTime / 1000
  end

  test "CrUX field data is parsed when present" do
    f = parsed[:data][:details][:field]
    assert f[:available]
    assert_equal 2400, f[:lcp_ms]
    assert_equal 180,  f[:inp_ms]
    assert_in_delta 0.02, f[:cls], 0.001                # percentile 2 / 100
    assert_equal "FAST", f[:category]
  end

  test "field data marked unavailable when loadingExperience has no metrics" do
    body = JSON.parse(file_fixture("pagespeed_example.json").read)
    body["loadingExperience"] = {}
    result = PagespeedParser.parse(body, strategy: "mobile")
    assert_not result[:data][:details][:field][:available]
  end

  test "recommendations are opportunities under score 1, ranked by savings, with sev + saving" do
    recs = parsed[:data][:recommendations]
    assert_equal 3, recs.size
    # render-blocking (900ms) ranks above optimized-images (600ms) above text-compression (0)
    assert_equal "Eliminate render-blocking resources", recs.first[:title]
    assert_equal "crit", recs.first[:sev]                # score 0.30
    assert_equal "~0.9s", recs.first[:saving]
    imgs = recs.find { |r| r[:title] == "Serve images in next-gen formats" }
    assert_equal "~420 KB", imgs[:saving]                # bytes preferred over ms
    txt = recs.find { |r| r[:title] == "Enable text compression" }
    assert_equal "warn", txt[:sev]                       # score 0.60
    assert_equal "~180 KB", txt[:saving]
  end

  test "issues mirror crit/warn recommendations with string keys" do
    issues = parsed[:issues]
    assert_equal 3, issues.size
    assert(issues.all? { |i| i.key?("severity") && i.key?("title") })
    assert_equal 2, issues.count { |i| i["severity"] == "critical" }
    assert_equal 1, issues.count { |i| i["severity"] == "warning" }
  end

  test "waterfall has one row per request with timing and type" do
    wf = parsed[:data][:waterfall]
    assert_equal 5, wf.size
    assert_equal 1, wf.first[:n]
    assert_equal "html", wf.first[:type]                 # Document -> html
    assert_equal "js", wf.find { |r| r[:url].include?("bundle") }[:type]
    assert_equal 1400, wf.find { |r| r[:url].include?("hero") }[:end_ms]
  end

  test "summary names score, LCP, requests, size and strategy" do
    assert_equal "Perf 72 · LCP 3.1 s · 5 requests · 885 KB (mobile)", parsed[:summary]
  end
end
