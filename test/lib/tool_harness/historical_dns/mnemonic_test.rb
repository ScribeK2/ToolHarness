require "test_helper"

class ToolHarness::HistoricalDns::MnemonicTest < ActiveSupport::TestCase
  def provider = ToolHarness::HistoricalDns::Mnemonic.new

  # mnemonic PassiveDNS v3 timestamps are epoch *milliseconds*.
  BODY = {
    "responseCode" => 200,
    "data" => [
      { "query" => "example.com", "answer" => "1.2.3.4", "rrtype" => "a",
        "firstSeenTimestamp" => 1_597_190_400_000, "lastSeenTimestamp" => 1_620_000_000_000 }, # 2020-08-12 → 2021-05-03
      { "query" => "example.com", "answer" => "2606:4700::6810:85e5", "rrtype" => "aaaa",
        "firstSeenTimestamp" => 1_700_000_000_000, "lastSeenTimestamp" => 1_700_000_000_000 },
      { "query" => "example.com", "answer" => "cdn.example.net.", "rrtype" => "cname",
        "firstSeenTimestamp" => 1_600_000_000_000, "lastSeenTimestamp" => 1_600_000_000_000 },
      # reverse rows where the domain is the ANSWER, not the QUERY — must be ignored
      { "query" => "4.3.2.1.in-addr.arpa", "answer" => "example.com", "rrtype" => "ptr",
        "firstSeenTimestamp" => 1_600_000_000_000, "lastSeenTimestamp" => 1_600_000_000_000 },
      { "query" => "other.com", "answer" => "example.com", "rrtype" => "cname",
        "firstSeenTimestamp" => 1_600_000_000_000, "lastSeenTimestamp" => 1_600_000_000_000 }
    ]
  }.freeze

  test "maps forward A/AAAA/CNAME rows to records with ms→date conversion and source" do
    p = provider
    p.stub(:http_get_json, ->(_url, *) { { status: 200, body: BODY } }) do
      out = p.fetch("example.com")
      assert_empty out[:subdomains]
      by_value = out[:records].index_by(&:value)

      assert_equal :a, by_value["1.2.3.4"].type
      assert_equal Date.new(2020, 8, 12), by_value["1.2.3.4"].first_seen
      assert_equal Date.new(2021, 5, 3),  by_value["1.2.3.4"].last_seen
      assert_equal ["mnemonic"], by_value["1.2.3.4"].sources

      assert_equal :aaaa, by_value["2606:4700::6810:85e5"].type
      assert_equal :cname, by_value["cdn.example.net"].type # trailing dot normalized away
    end
  end

  test "ignores reverse rows (query != domain) and non-forward rrtypes (ptr)" do
    p = provider
    p.stub(:http_get_json, ->(_url, *) { { status: 200, body: BODY } }) do
      out = p.fetch("example.com")
      values = out[:records].map(&:value)
      assert_equal 3, out[:records].size, "only the 3 forward A/AAAA/CNAME rows"
      assert_not_includes values, "example.com" # the ptr/reverse-cname answers
    end
  end

  test "non-hash / empty body yields no records without raising" do
    p = provider
    p.stub(:http_get_json, ->(_url, *) { { status: 200, body: [] } }) do
      assert_empty p.fetch("example.com")[:records]
    end
  end

  test "429 raises ProviderError(:rate_limited)" do
    p = provider
    err = p.stub(:http_get_json, ->(_url, *) { { status: 429, body: nil } }) do
      assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com") }
    end
    assert_equal :rate_limited, err.category
  end

  # mnemonic intermittently returns firstSeen/lastSeen == 0 while still populating
  # createdTimestamp/lastUpdatedTimestamp — fall back to those rather than emitting 1970.
  test "falls back to created/lastUpdated when firstSeen/lastSeen are zero" do
    row = { "responseCode" => 200, "data" => [
      { "query" => "example.com", "answer" => "9.9.9.9", "rrtype" => "a",
        "firstSeenTimestamp" => 0, "lastSeenTimestamp" => 0,
        "createdTimestamp" => 1_597_190_400_000, "lastUpdatedTimestamp" => 1_620_000_000_000 }
    ] }
    p = provider
    p.stub(:http_get_json, ->(_url, *) { { status: 200, body: row } }) do
      rec = p.fetch("example.com")[:records].first
      assert_equal Date.new(2020, 8, 12), rec.first_seen
      assert_equal Date.new(2021, 5, 3),  rec.last_seen
    end
  end

  test "is a free, no-key provider covering A/AAAA/CNAME" do
    assert_not ToolHarness::HistoricalDns::Mnemonic.requires_key?
    assert_equal %i[a aaaa cname], ToolHarness::HistoricalDns::Mnemonic.record_types
  end
end
