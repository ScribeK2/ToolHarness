require "test_helper"

class Investigations::EmailDeliveryCorrelatorTest < ActiveSupport::TestCase
  def run_for(key, data: {}, success: true, issues: [], status: nil)
    ToolRun.new(tool_key: key, tool_name: key, category: "email_auth",
                input: { "domain" => "example.com" },
                status: status || (success ? "completed" : "failed"),
                success: success, result_data: data, issues: issues)
  end

  def healthy_runs
    [
      run_for("dns_lookup", data: { "mx_records" => [{ "priority" => 10, "host" => "mx.example.com." }] }),
      run_for("spf_check", data: { "success" => true, "all_mechanism" => { "type" => "all", "qualifier" => "~" } }),
      run_for("dkim_check", data: { "selectors_found" => [{ "selector" => "google", "parsed" => { "flags" => "" } }] }),
      run_for("dmarc_check", data: { "success" => true, "policy" => "reject" }),
      run_for("hosting_diagnostic", data: { "open_ports" => ["smtp", "imaps"] }),
      run_for("blacklist", data: { "listings" => [] })
    ]
  end

  # Returns the healthy battery with one probe replaced (matched by tool_key).
  def runs_with(key, **overrides)
    healthy_runs.map { |r| r.tool_key == key ? run_for(key, **overrides) : r }
  end

  def codes(result) = result.findings.map { |f| f["code"] }

  test "fully healthy -> healthy verdict + single externally-healthy finding" do
    res = Investigations::EmailDeliveryCorrelator.new(healthy_runs).call
    assert_equal "healthy", res.verdict_status
    assert_equal ["mail_externally_healthy"], codes(res)
    assert_nil res.suggested_track
  end

  test "no MX -> critical no_mx" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("dns_lookup", data: { "mx_records" => [] })).call
    assert_equal "critical", res.verdict_status
    assert_includes codes(res), "no_mx"
  end

  test "MX present but no mail ports open -> critical smtp_unreachable" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("hosting_diagnostic", data: { "open_ports" => ["http", "https"] })).call
    assert_includes codes(res), "smtp_unreachable"
    assert_equal "critical", res.verdict_status
  end

  test "blacklisted on a major list -> critical mail_blacklisted" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("blacklist", data: { "listings" => [{ "name" => "Spamhaus ZEN" }] })).call
    bl = res.findings.find { |f| f["code"] == "mail_blacklisted" }
    assert_equal "critical", bl["severity"]
  end

  test "blacklisted on a minor list only -> warning" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("blacklist", data: { "listings" => [{ "name" => "SORBS" }] })).call
    bl = res.findings.find { |f| f["code"] == "mail_blacklisted" }
    assert_equal "warning", bl["severity"]
  end

  test "SPF over the lookup limit -> critical spf_permerror" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("spf_check", data: { "success" => true }, issues: [{ "code" => "too_many_lookups" }])).call
    assert_includes codes(res), "spf_permerror"
    assert_equal "critical", res.verdict_status
  end

  test "missing SPF -> warning spf_missing" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("spf_check", data: { "success" => false }, success: false)).call
    assert_includes codes(res), "spf_missing"
  end

  test "SPF without a restrictive all -> warning spf_permissive" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("spf_check", data: { "success" => true, "all_mechanism" => { "qualifier" => "+" } })).call
    assert_includes codes(res), "spf_permissive"
  end

  test "SPF record with no all mechanism at all -> warning spf_permissive" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("spf_check", data: { "success" => true })).call
    assert_includes codes(res), "spf_permissive"
  end

  test "no DKIM selector -> warning dkim_absent, caveated" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("dkim_check", data: { "selectors_found" => [] })).call
    f = res.findings.find { |x| x["code"] == "dkim_absent" }
    assert f
    assert_match(/common selector/i, f["message"])
  end

  test "DKIM in testing mode -> warning dkim_testing" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("dkim_check", data: { "selectors_found" => [{ "selector" => "k1", "parsed" => { "flags" => "y" } }] })).call
    assert_includes codes(res), "dkim_testing"
  end

  test "missing DMARC -> warning dmarc_missing" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("dmarc_check", data: { "success" => false }, success: false)).call
    assert_includes codes(res), "dmarc_missing"
  end

  test "DMARC p=none -> warning dmarc_policy_none" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("dmarc_check", data: { "success" => true, "policy" => "none" })).call
    assert_includes codes(res), "dmarc_policy_none"
  end

  test "a skipped blacklist run produces no blacklist finding" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("blacklist", data: {}, status: "skipped")).call
    assert_not_includes codes(res), "mail_blacklisted"
  end

  test "findings carry provenance" do
    res = Investigations::EmailDeliveryCorrelator.new(runs_with("dns_lookup", data: { "mx_records" => [] })).call
    no_mx = res.findings.find { |f| f["code"] == "no_mx" }
    assert_equal ["dns_lookup"], no_mx["provenance"]
  end
end
