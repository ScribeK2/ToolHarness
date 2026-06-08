require "test_helper"

class ToolHarness::HistoricalDns::RecordTest < ActiveSupport::TestCase
  N = ToolHarness::HistoricalDns::Normalize

  test "host normalization lowercases and strips trailing dot" do
    assert_equal "ns1.cloudflare.com", N.host("NS1.Cloudflare.com.")
    assert_equal "", N.host(nil)
  end

  test "mx canonicalizes to '<priority> <host>' and dedupes case/dot" do
    assert_equal "10 mail.example.com", N.mx(10, "Mail.Example.com.")
    assert_equal "mail.example.com", N.mx(nil, "mail.example.com")
  end

  test "text collapses whitespace and strips wrapping quotes" do
    assert_equal "v=spf1 include:_spf.google.com ~all",
                 N.text("\"v=spf1   include:_spf.google.com   ~all\"")
  end

  test "date parses epoch ints, ISO strings, and nil" do
    assert_equal Date.new(2020, 8, 12), N.date(1597190400)        # unix epoch (2020-08-12 UTC)
    assert_equal Date.new(2023, 1, 1),  N.date("2023-01-01T00:00:00")
    assert_nil N.date(nil)
    assert_nil N.date("")
  end

  test "Record is a value object keyed by [type, value]" do
    r = ToolHarness::HistoricalDns::Record.new(type: :a, value: "1.2.3.4",
          first_seen: Date.new(2021, 1, 1), last_seen: Date.new(2022, 1, 1), sources: ["x"])
    assert_equal [:a, "1.2.3.4"], r.key
    assert_equal "1.2.3.4", r.value
  end
end
