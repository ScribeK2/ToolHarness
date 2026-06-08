require "test_helper"

class ToolHarness::HistoricalDns::CrtshTest < ActiveSupport::TestCase
  def fetch_with(status:, body:, error: nil)
    p = ToolHarness::HistoricalDns::Crtsh.new
    p.stub(:http_get_json, ->(_url, *) { { status: status, body: body, error: error } }) do
      p.fetch("Example.com")
    end
  end

  ROWS = [
    { "name_value" => "example.com\nmail.example.com", "not_before" => "2023-01-01T00:00:00", "not_after" => "2023-04-01T00:00:00" },
    { "name_value" => "mail.example.com",              "not_before" => "2024-02-01T00:00:00", "not_after" => "2024-05-01T00:00:00" },
    { "name_value" => "*.example.com",                 "not_before" => "2023-01-01T00:00:00", "not_after" => "2023-04-01T00:00:00" },
    { "name_value" => "unrelated.org",                 "not_before" => "2023-01-01T00:00:00", "not_after" => "2023-04-01T00:00:00" }
  ].freeze

  test "parses subdomains, dedupes, widens window, drops wildcards and out-of-scope" do
    out = fetch_with(status: 200, body: ROWS)
    assert_empty out[:records]
    names = out[:subdomains].map { |s| s[:name] }
    assert_equal %w[example.com mail.example.com], names           # sorted, wildcard + unrelated dropped
    mail = out[:subdomains].find { |s| s[:name] == "mail.example.com" }
    assert_equal Date.new(2023, 1, 1), mail[:first_seen]           # widened across both certs
    assert_equal Date.new(2024, 5, 1), mail[:last_seen]
  end

  test "200 with non-array body yields empty" do
    out = fetch_with(status: 200, body: { "error" => "rate" })
    assert_equal({ records: [], subdomains: [] }, out)
  end

  test "non-200 raises ProviderError(:unavailable)" do
    err = assert_raises(ToolHarness::HistoricalDns::ProviderError) { fetch_with(status: 503, body: nil) }
    assert_equal :unavailable, err.category
  end
end
