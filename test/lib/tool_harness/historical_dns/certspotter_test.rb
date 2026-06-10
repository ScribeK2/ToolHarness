require "test_helper"

class ToolHarness::HistoricalDns::CertspotterTest < ActiveSupport::TestCase
  def provider = ToolHarness::HistoricalDns::Certspotter.new

  # Certspotter /v1/issuances returns a JSON array; each issuance has an id, dns_names,
  # not_before, not_after. first_seen/last_seen for a subdomain = min(not_before)/max(not_after).
  PAGE1 = [
    { "id" => "1", "dns_names" => %w[example.com www.example.com], "not_before" => "2021-01-01T00:00:00Z", "not_after" => "2022-01-01T00:00:00Z" },
    { "id" => "2", "dns_names" => %w[mail.example.com],            "not_before" => "2023-06-01T00:00:00Z", "not_after" => "2024-06-01T00:00:00Z" },
    { "id" => "3", "dns_names" => %w[www.example.com *.cdn.example.com other.org], "not_before" => "2024-01-01T00:00:00Z", "not_after" => "2025-01-01T00:00:00Z" }
  ].freeze
  PAGE2 = [
    { "id" => "4", "dns_names" => %w[api.example.com], "not_before" => "2025-02-01T00:00:00Z", "not_after" => "2026-02-01T00:00:00Z" }
  ].freeze

  # Pagination walks ?after=<last id> until an empty page.
  def paged_stub
    lambda do |url, *|
      if    url.include?("after=4") then { status: 200, body: [] }
      elsif url.include?("after=3") then { status: 200, body: PAGE2 }
      else                               { status: 200, body: PAGE1 }
      end
    end
  end

  test "collects subdomains with min(not_before)/max(not_after), following pagination by id" do
    p = provider
    p.stub(:http_get_json, paged_stub) do
      out = p.fetch("example.com")
      assert_empty out[:records]
      by_name = out[:subdomains].index_by { |s| s[:name] }

      # www seen across two issuances → widened first/last window
      assert_equal Date.new(2021, 1, 1), by_name["www.example.com"][:first_seen]
      assert_equal Date.new(2025, 1, 1), by_name["www.example.com"][:last_seen]
      assert_equal Date.new(2026, 2, 1), by_name["api.example.com"][:last_seen] # page 2 followed
      assert_includes by_name.keys, "example.com"
      assert_includes by_name.keys, "mail.example.com"
    end
  end

  test "drops wildcards and names outside the domain" do
    p = provider
    p.stub(:http_get_json, ->(url, *) { url.include?("after=") ? { status: 200, body: [] } : { status: 200, body: PAGE1 } }) do
      names = p.fetch("example.com")[:subdomains].map { |s| s[:name] }
      assert_not_includes names, "*.cdn.example.com"
      assert_not_includes names, "other.org"
    end
  end

  test "429 raises ProviderError(:rate_limited)" do
    p = provider
    err = p.stub(:http_get_json, ->(_url, *) { { status: 429, body: nil } }) do
      assert_raises(ToolHarness::HistoricalDns::ProviderError) { p.fetch("example.com") }
    end
    assert_equal :rate_limited, err.category
  end

  test "is a free, no-key CT-log subdomain provider" do
    assert_not ToolHarness::HistoricalDns::Certspotter.requires_key?
    assert_empty ToolHarness::HistoricalDns::Certspotter.record_types
  end
end
