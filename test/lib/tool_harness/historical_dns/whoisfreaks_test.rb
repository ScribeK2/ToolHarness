require "test_helper"

class ToolHarness::HistoricalDns::WhoisfreaksTest < ActiveSupport::TestCase
  def provider = ToolHarness::HistoricalDns::Whoisfreaks.new

  # Per-type fixtures keyed by the `type=` query param.
  BODIES = {
    "a"    => { "dnsRecords" => [{ "address" => "1.2.3.4", "firstSeen" => "2021-02-01", "lastSeen" => "2024-03-01" }] },
    "aaaa" => { "dnsRecords" => [] },
    "ns"   => { "dnsRecords" => [{ "target" => "NS1.OurHost.com.", "firstSeen" => "2021-02-01", "lastSeen" => "2024-03-01" },
                                 { "target" => "dana.ns.cloudflare.com", "firstSeen" => "2024-03-01", "lastSeen" => "2026-06-01" }] },
    "mx"   => { "dnsRecords" => [{ "priority" => 10, "target" => "mail.example.com.", "firstSeen" => "2021-02-01", "lastSeen" => "2026-06-01" }] },
    "txt"  => { "dnsRecords" => [{ "rawText" => "\"v=spf1 include:_spf.google.com ~all\"", "firstSeen" => "2022-01-01", "lastSeen" => "2026-06-01" }] }
  }.freeze

  def stub_fetch(p, bodies = BODIES, status: 200)
    p.stub(:http_get_json, lambda { |url, *|
      type = url[/type=([a-z]+)/, 1]
      { status: status, body: bodies.fetch(type, { "dnsRecords" => [] }) }
    }) { yield }
  end

  test "fetches each default record type and normalizes values + dates + source" do
    p = provider
    out = stub_fetch(p) { p.fetch("Example.com", key: "k") }
    recs = out[:records]
    assert_empty out[:subdomains]

    ns = recs.select { |r| r.type == :ns }.map(&:value).sort
    assert_equal ["dana.ns.cloudflare.com", "ns1.ourhost.com"], ns   # host-normalized
    a = recs.find { |r| r.type == :a }
    assert_equal "1.2.3.4", a.value
    assert_equal Date.new(2021, 2, 1), a.first_seen
    assert_equal ["whoisfreaks"], a.sources
    mx = recs.find { |r| r.type == :mx }
    assert_equal "10 mail.example.com", mx.value
    txt = recs.find { |r| r.type == :txt }
    assert_equal "v=spf1 include:_spf.google.com ~all", txt.value
    assert_equal %i[a ns mx txt].sort, recs.map(&:type).uniq.sort
  end

  test "401 raises ProviderError(:bad_key)" do
    p = provider
    err = stub_fetch(p, status: 401) { assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com", key: "k") } }
    assert_equal :bad_key, err.category
  end

  test "credit-exhaustion body raises ProviderError(:no_credits)" do
    p = provider
    body = { "error" => "Insufficient credits to process this request" }
    err = p.stub(:http_get_json, ->(_url, *) { { status: 400, body: body } }) do
      assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com", key: "k") }
    end
    assert_equal :no_credits, err.category
  end
end
