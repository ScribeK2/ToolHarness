require "test_helper"

# Renders the real custom partial through the actual ERB for each
# source/record_type, so a missing-key or nil-handling regression in the view
# is caught. result_data is string-keyed (DB round-trip); summary + issues are
# separate ToolRun columns, not keys inside result_data.
class WhoisLookupSourceRegressionTest < ActiveSupport::TestCase
  def render_partial(data)
    run = ToolRun.new(
      tool_key: "whois_lookup",
      tool_name: "Registration Lookup (RDAP / WHOIS)",
      status: "completed",
      result_data: data.deep_stringify_keys,
      summary: "ok",
      issues: []
    )
    ApplicationController.render(partial: "results/tools/whois_lookup", locals: { tool_run: run })
  end

  test "renders RDAP domain result" do
    html = render_partial(
      record_type: :domain, source: :rdap_registry, success: true,
      query: "example.com", registrar: "MarkMonitor", expiration_date: "2027-08-13",
      nameservers: %w[a.iana-servers.net], statuses: %w[clientTransferProhibited],
      entities: [], raw_data: "{}"
    )
    assert_match "MarkMonitor", html
    assert_match(/RDAP/i, html)
  end

  test "renders RDAP ip result" do
    html = render_partial(
      record_type: :ip, source: :rdap_registry, success: true,
      query: "8.8.8.8", network_name: "GOGL", cidr: "8.8.8.0/24", organization: "Google LLC",
      abuse_contact: "abuse@google.com", country: "US", events: [], entities: [], raw_data: "{}"
    )
    assert_match "GOGL", html
    assert_match "abuse@google.com", html
  end

  test "renders WHOIS fallback result without rdap-only keys" do
    html = render_partial(
      record_type: :domain, source: :whois_fallback, success: true,
      query: "example.com", registrar: "Reg", expiration_date: nil, nameservers: [],
      raw_data: "raw text"
    )
    assert_match(/WHOIS/i, html)
  end

  # The raw blob must use the shared kv_row surface so it gets the universal
  # [data-truncated] toggle (the `:raw` cmdline verb) + click-to-copy, not a
  # hand-rolled <details>. A multi-line raw value triggers the truncation path.
  test "raw block uses the shared truncation + click-to-copy surface" do
    multiline = (1..10).map { |i| %(  "k#{i}": #{i},) }.join("\n")
    html = render_partial(
      record_type: :domain, source: :rdap_registry, success: true,
      query: "example.com", registrar: "Reg", nameservers: [], statuses: [],
      entities: [], raw_data: "{\n#{multiline}\n}"
    )
    assert_match "data-truncated", html, "raw must be `:raw`-expandable"
    refute_match "show raw", html, "the hand-rolled <details> should be gone"
    # Both the truncated-head AND the expanded-full views must be click-to-copy.
    head_copyable = html =~ /data-truncated-head[^>]*data-copy-value|data-copy-value[^>]*data-truncated-head/
    full_copyable = html =~ /data-truncated-full[^>]*data-copy-value|data-copy-value[^>]*data-truncated-full/
    assert head_copyable, "truncated raw must be click-to-copy"
    assert full_copyable, "expanded raw must also be click-to-copy"
  end

  # RDAP results: Raw block shows whois_text by default; the literal JSON is a
  # hidden sibling that the `:json` cmdline verb reveals.
  test "RDAP raw block defaults to whois_text with json source hidden" do
    html = render_partial(
      record_type: :domain, source: :rdap_registry, success: true,
      query: "example.com", registrar: "Reg", nameservers: [], statuses: [], entities: [],
      whois_text: "Domain Name: example.com\nRegistrar: Reg",
      raw_data: "{\n  \"ldhName\": \"example.com\"\n}"
    )
    assert_match 'data-rdap-format="whois"', html
    assert_match 'data-rdap-format="json"', html
    assert_match "Domain Name: example.com", html
    # The json block carries the `hidden` class so whois shows first.
    assert_match(/data-rdap-format="json"[^>]*class="[^"]*hidden/, html,
                 "json source block must start hidden")
  end

  # WHOIS fallback has no RDAP JSON to reformat — raw_data is already whois-style
  # text, so there is no whois/json toggle.
  test "WHOIS fallback (no whois_text) shows raw text and no json toggle" do
    html = render_partial(
      record_type: :domain, source: :whois_fallback, success: true,
      query: "example.com", registrar: "Reg", nameservers: [],
      raw_data: "Domain Name: EXAMPLE.COM\nRegistrar: Reg"
    )
    refute_match 'data-rdap-format="json"', html
    assert_match "Domain Name: EXAMPLE.COM", html
  end
end
