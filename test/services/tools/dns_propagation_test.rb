# test/services/tools/dns_propagation_test.rb
require "test_helper"

class Tools::DnsPropagationTest < ActiveSupport::TestCase
  test "static metadata" do
    assert_equal "DNS Propagation", Tools::DnsPropagation.tool_name
    assert_equal :dns,              Tools::DnsPropagation.category
    assert_equal :domain,           Tools::DnsPropagation.input_type
    refute Tools::DnsPropagation.cacheable?
    assert_equal "results/tools/dns_propagation", Tools::DnsPropagation.result_partial
  end

  test "form_fields exposes domain and record_type select" do
    ff = Tools::DnsPropagation.form_fields
    assert_equal :text, ff[:domain]
    assert_equal :select, ff[:record_type][:type]
    assert_equal %w[A AAAA MX NS CNAME TXT SOA CAA], ff[:record_type][:options]
  end

  test "registered in the registry under :dns_propagation" do
    assert_equal Tools::DnsPropagation, ToolHarness::Registry.find_tool(:dns_propagation)
    assert_includes ToolHarness::Registry.tools_for_category(:dns), Tools::DnsPropagation
  end

  test "summary: fully propagated, no failures" do
    raw = {
      success: true, domain: "example.com", record_type: "A",
      resolvers: Array.new(20) { |i| { status: :ok, values: ["1.2.3.4"] } },
      consensus: { value: ["1.2.3.4"], count: 20, total: 20 },
      dissenters: [], failures: [], issues: []
    }
    summary = Tools::DnsPropagation.new.send(:build_summary, raw)
    assert_equal "A record fully propagated to 20/20 resolvers.", summary
  end

  test "summary: partial propagation includes dissent + failure counts" do
    raw = {
      success: true, domain: "example.com", record_type: "A",
      resolvers: Array.new(20) { { status: :ok } },
      consensus: { value: ["1.2.3.4"], count: 18, total: 19 },
      dissenters: [{ status: :ok }],
      failures: [{ status: :timeout }],
      issues: []
    }
    summary = Tools::DnsPropagation.new.send(:build_summary, raw)
    assert_equal "A record fully propagated to 18/19 resolvers (1 dissent, 1 failure).", summary
  end

  test "summary: no consensus" do
    raw = {
      success: true, domain: "example.com", record_type: "A",
      resolvers: Array.new(18) { { status: :ok } },
      consensus: nil,
      dissenters: Array.new(18) { { values: ["1.2.3.4"] } },
      failures: [],
      issues: []
    }
    # Distinct values produced by dissenters list — set 4 unique in this fixture:
    raw[:dissenters] = [
      *Array.new(5) { { values: ["1.1.1.1"] } },
      *Array.new(5) { { values: ["2.2.2.2"] } },
      *Array.new(4) { { values: ["3.3.3.3"] } },
      *Array.new(4) { { values: ["4.4.4.4"] } }
    ]
    summary = Tools::DnsPropagation.new.send(:build_summary, raw)
    assert_equal "No DNS propagation consensus — 4 distinct values across 18 resolvers.", summary
  end

  test "summary: NXDOMAIN sweep" do
    raw = {
      success: false, domain: "missing.example", record_type: "A",
      resolvers: Array.new(20) { { status: :nxdomain } },
      consensus: nil, dissenters: [], failures: Array.new(20) { { status: :nxdomain } },
      issues: [{ code: "nxdomain_consensus" }]
    }
    summary = Tools::DnsPropagation.new.send(:build_summary, raw)
    assert_equal "Domain missing.example does not exist (NXDOMAIN across all 20 resolvers).", summary
  end

  test "summary: all-failed (no resolver responded)" do
    raw = {
      success: false, domain: "example.com", record_type: "A",
      resolvers: Array.new(20) { { status: :timeout } },
      consensus: nil, dissenters: [], failures: Array.new(20) { { status: :timeout } },
      issues: []
    }
    summary = Tools::DnsPropagation.new.send(:build_summary, raw)
    assert_equal "No resolver responded — 20 of 20 failed.", summary
  end

  test "summary: partial propagation with multiple dissenters/failures pluralizes" do
    raw = {
      success: true, domain: "example.com", record_type: "A",
      resolvers: Array.new(20) { { status: :ok } },
      consensus: { value: ["1.2.3.4"], count: 15, total: 18 },
      dissenters: Array.new(3) { { status: :ok } },
      failures: Array.new(2) { { status: :timeout } },
      issues: []
    }
    summary = Tools::DnsPropagation.new.send(:build_summary, raw)
    assert_equal "A record fully propagated to 15/18 resolvers (3 dissents, 2 failures).", summary
  end
end
