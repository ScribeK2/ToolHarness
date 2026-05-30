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
end
