require "test_helper"

class Rdap::BootstrapTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  # Minimal IANA dns.json shape: services = [[tlds...], [rdap base urls...]]
  DNS_JSON = {
    "services" => [
      [["com", "net"], ["https://rdap.verisign.com/com/v1/"]],
      [["org"],        ["https://rdap.publicinterestregistry.org/rdap/"]]
    ]
  }.freeze

  test "fetch_json is the single HTTP seam and its result is cached" do
    calls = 0
    fetcher = ->(_url) { calls += 1; DNS_JSON }
    boot = Rdap::Bootstrap.new
    boot.stub(:fetch_json, fetcher) do
      assert_equal DNS_JSON, boot.send(:dns_services)
      assert_equal DNS_JSON, boot.send(:dns_services) # second call hits cache
    end
    assert_equal 1, calls, "expected dns.json fetched once then cached"
  end

  test "base_for resolves a domain to its registry by longest TLD match" do
    boot = Rdap::Bootstrap.new
    boot.stub(:fetch_json, ->(_) { DNS_JSON }) do
      assert_equal "https://rdap.verisign.com/com/v1/", boot.base_for("example.com", :domain)
      assert_equal "https://rdap.publicinterestregistry.org/rdap/", boot.base_for("nonprofit.org", :domain)
    end
  end

  test "base_for returns nil for an unknown TLD" do
    boot = Rdap::Bootstrap.new
    boot.stub(:fetch_json, ->(_) { DNS_JSON }) do
      assert_nil boot.base_for("example.zzz", :domain)
    end
  end

  IPV4_JSON = {
    "services" => [
      [["8.0.0.0/8"],   ["https://rdap.arin.net/registry/"]],
      [["8.8.0.0/16"],  ["https://rdap.example-more-specific.net/"]],
      [["193.0.0.0/8"], ["https://rdap.db.ripe.net/"]]
    ]
  }.freeze

  IPV6_JSON = {
    "services" => [
      [["2001:200::/23"], ["https://rdap.apnic.net/"]]
    ]
  }.freeze

  test "base_for resolves an IPv4 to the most specific RIR block" do
    boot = Rdap::Bootstrap.new
    boot.stub(:fetch_json, ->(url) { url.include?("ipv4") ? IPV4_JSON : nil }) do
      # 8.8.8.8 matches both /8 and /16 -> pick the longer prefix
      assert_equal "https://rdap.example-more-specific.net/", boot.base_for("8.8.8.8", :ip)
      assert_equal "https://rdap.arin.net/registry/", boot.base_for("8.1.1.1", :ip)
    end
  end

  test "base_for resolves an IPv6 address" do
    boot = Rdap::Bootstrap.new
    boot.stub(:fetch_json, ->(url) { url.include?("ipv6") ? IPV6_JSON : nil }) do
      assert_equal "https://rdap.apnic.net/", boot.base_for("2001:200:0:1::1", :ip)
    end
  end

  test "base_for returns nil for an IP in no known block" do
    boot = Rdap::Bootstrap.new
    boot.stub(:fetch_json, ->(url) { url.include?("ipv4") ? IPV4_JSON : nil }) do
      assert_nil boot.base_for("203.0.113.5", :ip)
    end
  end
end
