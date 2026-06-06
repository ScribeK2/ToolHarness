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
end
