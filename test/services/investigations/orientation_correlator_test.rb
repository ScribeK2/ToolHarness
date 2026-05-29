# test/services/investigations/orientation_correlator_test.rb
require "test_helper"

class Investigations::OrientationCorrelatorTest < ActiveSupport::TestCase
  # Helpers to fabricate child runs with the real result_data shapes.
  def whois(data: {}, success: true)
    ToolRun.new(tool_key: "whois_lookup", tool_name: "WHOIS", category: "domain",
                input: { "domain" => "example.com" }, status: success ? "completed" : "failed",
                success: success, result_data: data)
  end

  def dns(data: {}, success: true)
    ToolRun.new(tool_key: "dns_lookup", tool_name: "DNS", category: "dns",
                input: { "domain" => "example.com" }, status: success ? "completed" : "failed",
                success: success, result_data: data)
  end

  def hosting(data: {}, success: true)
    ToolRun.new(tool_key: "hosting_diagnostic", tool_name: "Hosting", category: "hosting",
                input: { "domain" => "example.com" }, status: success ? "completed" : "failed",
                success: success, result_data: data)
  end

  def codes(result) = result.findings.map { |f| f["code"] }

  test "all healthy -> healthy verdict + single externally_healthy finding" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601, "nameservers" => ["ns1.foo.com", "ns2.foo.com"] }),
      dns(data: { "a_records" => ["1.2.3.4"], "aaaa_records" => [], "cname_records" => [],
                  "ns_records" => ["ns1.foo.com.", "ns2.foo.com."],
                  "mx_records" => [{ "priority" => 10, "host" => "mail.foo.com." }] }),
      hosting(data: { "open_ports" => ["http", "https", "smtp"], "server_banner" => { "server" => "nginx" } })
    ]).call

    assert_equal "healthy", res.verdict_status
    assert_equal ["externally_healthy"], codes(res)
  end

  test "expired domain -> critical, ranked first" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today - 5).iso8601, "nameservers" => ["ns1.foo.com."] }),
      dns(data: { "a_records" => ["1.2.3.4"], "ns_records" => ["ns1.foo.com."], "mx_records" => [{ "host" => "m." }] }),
      hosting(data: { "open_ports" => ["http", "https", "smtp"] })
    ]).call

    assert_equal "critical", res.verdict_status
    assert_equal "domain_expired", codes(res).first
  end

  test "expiring within 30 days -> warning" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 10).iso8601 }),
      dns(data: { "a_records" => ["1.2.3.4"], "mx_records" => [{ "host" => "m." }] }),
      hosting(data: { "open_ports" => ["http", "smtp"] })
    ]).call
    assert_includes codes(res), "domain_expiring"
    assert_equal "issues", res.verdict_status
  end

  test "no resolution -> critical no_resolution" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601 }),
      dns(data: { "a_records" => [], "aaaa_records" => [], "cname_records" => [] }),
      hosting(data: { "open_ports" => [] })
    ]).call
    assert_includes codes(res), "no_resolution"
    assert_equal "critical", res.verdict_status
  end

  test "NS mismatch (trailing-dot normalized) -> warning" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601, "nameservers" => ["ns1.registrar.com", "ns2.registrar.com"] }),
      dns(data: { "a_records" => ["1.2.3.4"], "ns_records" => ["ns1.cloudflare.com.", "ns2.cloudflare.com."],
                  "mx_records" => [{ "host" => "m." }] }),
      hosting(data: { "open_ports" => ["http", "https", "smtp"] })
    ]).call
    assert_includes codes(res), "ns_mismatch"
  end

  test "identical nameservers (one dotted, one not) -> no mismatch" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601, "nameservers" => ["NS1.Foo.com", "ns2.foo.com"] }),
      dns(data: { "a_records" => ["1.2.3.4"], "ns_records" => ["ns2.foo.com.", "ns1.foo.com."],
                  "mx_records" => [{ "host" => "m." }] }),
      hosting(data: { "open_ports" => ["http", "https", "smtp"] })
    ]).call
    assert_not_includes codes(res), "ns_mismatch"
  end

  test "resolves but no web ports -> critical resolves_not_serving" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601 }),
      dns(data: { "a_records" => ["1.2.3.4"], "ns_records" => ["ns1.foo.com."], "mx_records" => [{ "host" => "m." }] }),
      hosting(data: { "open_ports" => ["smtp"] })  # mail up, web down
    ]).call
    assert_includes codes(res), "resolves_not_serving"
    assert_equal "critical", res.verdict_status
  end

  test "no MX -> warning no_mx" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601 }),
      dns(data: { "a_records" => ["1.2.3.4"], "ns_records" => ["ns1.foo.com."], "mx_records" => [] }),
      hosting(data: { "open_ports" => ["http", "https"] })
    ]).call
    assert_includes codes(res), "no_mx"
  end

  test "MX present but mail ports closed -> warning mail_ports_closed" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601 }),
      dns(data: { "a_records" => ["1.2.3.4"], "ns_records" => ["ns1.foo.com."], "mx_records" => [{ "host" => "m.foo.com." }] }),
      hosting(data: { "open_ports" => ["http", "https"] })  # no mail ports
    ]).call
    assert_includes codes(res), "mail_ports_closed"
  end

  test "suggested_track is email_delivery when MX present" do
    res = Investigations::OrientationCorrelator.new([
      whois, dns(data: { "a_records" => ["1.2.3.4"], "mx_records" => [{ "host" => "m." }] }),
      hosting(data: { "open_ports" => ["http"] })
    ]).call
    assert_equal "email_delivery", res.suggested_track
  end

  test "suggested_track is hosting_website when web up and no MX" do
    res = Investigations::OrientationCorrelator.new([
      whois, dns(data: { "a_records" => ["1.2.3.4"], "mx_records" => [] }),
      hosting(data: { "open_ports" => ["https"] })
    ]).call
    assert_equal "hosting_website", res.suggested_track
  end

  test "findings carry provenance" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today - 1).iso8601 }),
      dns(data: { "a_records" => ["1.2.3.4"], "mx_records" => [{ "host" => "m." }] }),
      hosting(data: { "open_ports" => ["http", "https", "smtp"] })
    ]).call
    expired = res.findings.find { |f| f["code"] == "domain_expired" }
    assert_equal ["whois_lookup"], expired["provenance"]
  end

  test "failed DNS run fires no_resolution only, not resolves_not_serving or no_mx" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601 }),
      dns(data: { "a_records" => ["1.2.3.4"], "mx_records" => [] }, success: false),
      hosting(data: { "open_ports" => [] })
    ]).call
    assert_includes codes(res), "no_resolution"
    assert_not_includes codes(res), "resolves_not_serving"
    assert_not_includes codes(res), "no_mx"
    assert_equal "critical", res.verdict_status
  end

  test "suggested_track is nil when no MX and nothing serving" do
    res = Investigations::OrientationCorrelator.new([
      whois(data: { "expiration_date" => (Date.today + 200).iso8601 }),
      dns(data: { "a_records" => ["1.2.3.4"], "mx_records" => [] }),
      hosting(data: { "open_ports" => [], "server_banner" => nil })
    ]).call
    assert_nil res.suggested_track
  end

  test "degrades gracefully when only the whois run is present" do
    assert_nothing_raised do
      Investigations::OrientationCorrelator.new([
        whois(data: { "expiration_date" => (Date.today + 200).iso8601 })
      ]).call
    end
  end
end
