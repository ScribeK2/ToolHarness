require "test_helper"

class Tools::DnsLookupTest < ActiveSupport::TestCase
  test "form_fields exposes domain, depth select (quick default), record_type select" do
    ff = Tools::DnsLookup.form_fields
    assert_equal :text, ff[:domain]
    assert_equal %w[quick worldwide], ff[:depth][:options]
    assert_equal %w[A AAAA MX NS CNAME TXT SOA CAA], ff[:record_type][:options]
  end

  test "dns_propagation is no longer registered" do
    assert_nil ToolHarness::Registry.find_tool(:dns_propagation)
  end

  test "quick depth (and default) uses DnsChecker" do
    canned = { success: true, a_records: ["1.2.3.4"], aaaa_records: [], mx_records: [],
               ns_records: [], cname_records: [], issues: [] }
    DnsChecker.stub(:check, canned) do
      res = Tools::DnsLookup.new.execute(domain: "example.com")
      assert res.success
      assert_match(/Resolves to 1\.2\.3\.4/, res.summary)
    end
  end

  test "worldwide depth uses PropagationChecker with the record type" do
    canned = { success: true, domain: "example.com", record_type: "MX",
               resolvers: Array.new(20) { { status: :ok } },
               consensus: { value: ["mx1"], count: 20, total: 20 },
               dissenters: [], failures: [], issues: [] }
    captured = nil
    PropagationChecker.stub(:check, ->(domain, record_type:) { captured = [domain, record_type]; canned }) do
      res = Tools::DnsLookup.new.execute(domain: "example.com", depth: "worldwide", record_type: "MX")
      assert res.success
      assert_equal ["example.com", "MX"], captured
      assert_equal "MX record fully propagated to 20/20 resolvers.", res.summary
    end
  end

  test "worldwide summary: no consensus" do
    raw = { success: true, domain: "example.com", record_type: "A",
            resolvers: Array.new(20) { { status: :ok } }, consensus: nil,
            dissenters: [{ values: ["1.1.1.1"] }, { values: ["2.2.2.2"] }],
            failures: [], issues: [] }
    summary = Tools::DnsLookup.new.send(:propagation_summary, raw)
    assert_match(/No DNS propagation consensus/, summary)
  end

  test "worldwide summary: nxdomain sweep" do
    raw = { success: true, domain: "gone.example", record_type: "A",
            resolvers: Array.new(20) { { status: :nxdomain } }, consensus: nil,
            dissenters: [], failures: [],
            issues: [{ code: "nxdomain_consensus" }] }
    summary = Tools::DnsLookup.new.send(:propagation_summary, raw)
    assert_match(/does not exist \(NXDOMAIN/, summary)
  end

  # --- Ported from dns_propagation_test.rb ---

  test "propagation_summary: all-resolvers-failed (no resolver responded)" do
    raw = {
      success: false, domain: "example.com", record_type: "A",
      resolvers: Array.new(20) { { status: :timeout } },
      consensus: nil, dissenters: [], failures: Array.new(20) { { status: :timeout } },
      issues: []
    }
    summary = Tools::DnsLookup.new.send(:propagation_summary, raw)
    assert_equal "No resolver responded — 20 of 20 failed.", summary
  end

  test "propagation_summary: partial propagation includes dissent + failure counts" do
    raw = {
      success: true, domain: "example.com", record_type: "A",
      resolvers: Array.new(20) { { status: :ok } },
      consensus: { value: ["1.2.3.4"], count: 18, total: 19 },
      dissenters: [{ status: :ok }],
      failures: [{ status: :timeout }],
      issues: []
    }
    summary = Tools::DnsLookup.new.send(:propagation_summary, raw)
    assert_equal "A record fully propagated to 18/19 resolvers (1 dissent, 1 failure).", summary
  end

  test "propagation_summary: partial propagation with multiple dissenters/failures pluralizes" do
    raw = {
      success: true, domain: "example.com", record_type: "A",
      resolvers: Array.new(20) { { status: :ok } },
      consensus: { value: ["1.2.3.4"], count: 15, total: 18 },
      dissenters: Array.new(3) { { status: :ok } },
      failures: Array.new(2) { { status: :timeout } },
      issues: []
    }
    summary = Tools::DnsLookup.new.send(:propagation_summary, raw)
    assert_equal "A record fully propagated to 15/18 resolvers (3 dissents, 2 failures).", summary
  end
end
