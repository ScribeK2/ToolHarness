require "test_helper"

# Renders the custom partial for each source/record_type so a missing-key or
# nil-handling regression in the view is caught. summary + issues are separate
# ToolRun columns (not keys inside result_data).
class WhoisLookupSourceRegressionTest < ActionView::TestCase
  def render_for(data, summary: "ok", issues: [])
    run = ToolRun.new(
      tool_key: "whois_lookup", status: "completed",
      input: { domain: data[:query] }, result_data: data.deep_stringify_keys,
      summary: summary, issues: issues
    )
    render partial: "results/tools/whois_lookup", locals: { tool_run: run }
  end

  test "renders RDAP domain result" do
    html = render_for(
      record_type: :domain, source: :rdap_registry, success: true,
      query: "example.com", registrar: "MarkMonitor", expiration_date: "2027-08-13",
      nameservers: %w[a.iana-servers.net], statuses: %w[clientTransferProhibited],
      entities: [], raw_data: "{}"
    )
    assert_match "MarkMonitor", html
    assert_match(/RDAP/i, html)
  end

  test "renders RDAP ip result" do
    html = render_for(
      record_type: :ip, source: :rdap_registry, success: true,
      query: "8.8.8.8", network_name: "GOGL", cidr: "8.8.8.0/24", organization: "Google LLC",
      abuse_contact: "abuse@google.com", country: "US", events: [], entities: [], raw_data: "{}"
    )
    assert_match "GOGL", html
    assert_match "abuse@google.com", html
  end

  test "renders WHOIS fallback result without rdap-only keys" do
    html = render_for(
      record_type: :domain, source: :whois_fallback, success: true,
      query: "example.com", registrar: "Reg", expiration_date: nil, nameservers: [],
      raw_data: "raw text"
    )
    assert_match(/WHOIS/i, html)
  end
end
