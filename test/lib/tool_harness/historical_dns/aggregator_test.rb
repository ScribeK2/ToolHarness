require "test_helper"

class ToolHarness::HistoricalDns::AggregatorTest < ActiveSupport::TestCase
  R = ToolHarness::HistoricalDns::Record

  def rec(type, value, fs, ls, src) = R.new(type: type, value: value, first_seen: fs, last_seen: ls, sources: [src])

  test "merges the same record across providers: union sources, widened window" do
    records = [
      rec(:a, "1.2.3.4", Date.new(2021, 1, 1), Date.new(2023, 1, 1), "mnemonic"),
      rec(:a, "1.2.3.4", Date.new(2020, 6, 1), Date.new(2024, 1, 1), "virustotal")
    ]
    out = ToolHarness::HistoricalDns::Aggregator.call(records)
    a = out[:timeline][:a]
    assert_equal 1, a.size
    assert_equal Date.new(2020, 6, 1), a.first[:first_seen]
    assert_equal Date.new(2024, 1, 1), a.first[:last_seen]
    assert_equal %w[mnemonic virustotal].sort, a.first[:sources].sort
  end

  test "marks current = records sharing the latest last_seen for the type" do
    records = [
      rec(:a, "1.1.1.1", Date.new(2021, 1, 1), Date.new(2024, 3, 1), "mnemonic"),
      rec(:a, "2.2.2.2", Date.new(2024, 3, 1), Date.new(2026, 6, 1), "mnemonic")
    ]
    a = ToolHarness::HistoricalDns::Aggregator.call(records)[:timeline][:a]
    assert_equal({ "1.1.1.1" => false, "2.2.2.2" => true }, a.to_h { |m| [m[:value], m[:current]] })
  end

  test "derives per-type change transitions between eras (multi-value era grouped)" do
    records = [
      rec(:ns, "ns1.ourhost.com",        Date.new(2021, 2, 1), Date.new(2024, 3, 1), "livedns"),
      rec(:ns, "dana.ns.cloudflare.com", Date.new(2024, 3, 1), Date.new(2026, 6, 1), "livedns"),
      rec(:ns, "kurt.ns.cloudflare.com", Date.new(2024, 3, 1), Date.new(2026, 6, 1), "livedns")
    ]
    changes = ToolHarness::HistoricalDns::Aggregator.call(records)[:changes]
    assert_equal 1, changes.size
    c = changes.first
    assert_equal :ns, c[:type]
    assert_equal ["ns1.ourhost.com"], c[:from]
    assert_equal ["dana.ns.cloudflare.com", "kurt.ns.cloudflare.com"].sort, c[:to].sort
    assert_equal "2024-03", c[:approx_date]
  end

  test "no changes when a type has a single era" do
    records = [rec(:mx, "10 mail.example.com", Date.new(2021, 1, 1), Date.new(2026, 1, 1), "livedns")]
    assert_empty ToolHarness::HistoricalDns::Aggregator.call(records)[:changes]
  end
end
