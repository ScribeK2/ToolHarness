require "test_helper"

class ToolHarness::HistoricalDns::VirustotalTest < ActiveSupport::TestCase
  def provider = ToolHarness::HistoricalDns::Virustotal.new

  PAGE1 = {
    "data" => [
      { "attributes" => { "ip_address" => "1.2.3.4", "date" => 1597190400 } },             # 2020-08-12
      { "attributes" => { "ip_address" => "2606:4700::6810:85e5", "date" => 1700000000 } } # ipv6
    ],
    "links" => { "next" => "https://www.virustotal.com/api/v3/domains/example.com/resolutions?cursor=PG2" }
  }.freeze
  PAGE2 = { "data" => [ { "attributes" => { "ip_address" => "5.6.7.8", "date" => 1620000000 } } ] }.freeze

  test "maps resolutions to A/AAAA records with dates and source, following pagination" do
    p = provider
    p.stub(:http_get_json, ->(url, *) { url.include?("cursor=PG2") ? { status: 200, body: PAGE2 } : { status: 200, body: PAGE1 } }) do
      out = p.fetch("example.com", key: "tok")
      assert_empty out[:subdomains]
      by_value = out[:records].index_by(&:value)
      assert_equal :a,    by_value["1.2.3.4"].type
      assert_equal Date.new(2020, 8, 12), by_value["1.2.3.4"].first_seen
      assert_equal ["virustotal"], by_value["1.2.3.4"].sources
      assert_equal :aaaa, by_value["2606:4700::6810:85e5"].type
      assert_equal :a,    by_value["5.6.7.8"].type   # page 2 followed
    end
  end

  test "401 raises ProviderError(:bad_key)" do
    p = provider
    err = p.stub(:http_get_json, ->(_url, *) { { status: 401, body: nil } }) do
      assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com", key: "tok") }
    end
    assert_equal :bad_key, err.category
  end

  test "429 raises ProviderError(:rate_limited)" do
    p = provider
    err = p.stub(:http_get_json, ->(_url, *) { { status: 429, body: nil } }) do
      assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com", key: "tok") }
    end
    assert_equal :rate_limited, err.category
  end
end
