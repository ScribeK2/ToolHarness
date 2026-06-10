require "test_helper"

class ToolHarness::HistoricalDns::LivednsTest < ActiveSupport::TestCase
  def provider = ToolHarness::HistoricalDns::Livedns.new

  # The live-resolution seam returns the current records by type, normalized the way
  # Resolv hands them back (MX as [preference, exchange]; everything else as strings).
  SNAPSHOT = {
    ns:    ["ns1.host.com.", "ns2.host.com."],
    mx:    [[10, "mail.host.com."], [20, "alt.host.com."]],
    a:     ["1.2.3.4"],
    aaaa:  ["2606:4700::1"],
    txt:   ["v=spf1 include:_spf.host.com -all"],
    soa:   ["ns1.host.com."],
    cname: []
  }.freeze

  test "turns the current snapshot into records dated today (first==last) tagged livedns" do
    p = provider
    p.stub(:resolve_all, ->(_d) { SNAPSHOT }) do
      out = p.fetch("example.com")
      assert_empty out[:subdomains]
      by_key = out[:records].group_by(&:type)

      assert_equal %w[ns1.host.com ns2.host.com], by_key[:ns].map(&:value).sort
      ns = by_key[:ns].first
      assert_equal ["livedns"], ns.sources
      assert_equal ns.first_seen, ns.last_seen, "a current snapshot has first_seen == last_seen"
      assert_kind_of Date, ns.first_seen

      assert_equal ["10 mail.host.com", "20 alt.host.com"], by_key[:mx].map(&:value).sort
      assert_equal ["1.2.3.4"],     by_key[:a].map(&:value)
      assert_equal ["2606:4700::1"], by_key[:aaaa].map(&:value)
      assert_equal ["v=spf1 include:_spf.host.com -all"], by_key[:txt].map(&:value)
      assert_equal ["ns1.host.com"], by_key[:soa].map(&:value)
    end
  end

  test "a domain with no records resolves to an empty (non-raising) result" do
    p = provider
    empty = { ns: [], mx: [], a: [], aaaa: [], txt: [], soa: [], cname: [] }
    p.stub(:resolve_all, ->(_d) { empty }) do
      out = p.fetch("nodata.example")
      assert_empty out[:records]
    end
  end

  test "a resolver failure raises ProviderError(:unavailable)" do
    p = provider
    p.stub(:resolve_all, ->(_d) { raise Resolv::ResolvError, "no nameservers" }) do
      err = assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com") }
      assert_equal :unavailable, err.category
    end
  end

  test "is a free, no-key provider covering the records passive DNS misses (NS/MX/SOA)" do
    assert_not ToolHarness::HistoricalDns::Livedns.requires_key?
    assert_includes ToolHarness::HistoricalDns::Livedns.record_types, :ns
    assert_includes ToolHarness::HistoricalDns::Livedns.record_types, :mx
  end
end
