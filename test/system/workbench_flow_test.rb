require "application_system_test_case"

class WorkbenchFlowTest < ApplicationSystemTestCase
  # Deterministic RDAP result so the test exercises the run → stream/poll → "done"
  # flow without a live network lookup. Mirrors the stub in the unit-level
  # Tools::WhoisLookup test. RdapChecker.check is a class method, so the stub is
  # process-global and reaches the Capybara server thread.
  RDAP_RESULT = {
    success: true, record_type: :domain, source: :rdap_registry,
    query: "example.com", registrar: "MarkMonitor Inc.", expiration_date: "2027-08-13",
    creation_date: nil, updated_date: nil, nameservers: %w[a.iana-servers.net],
    registrant: nil, statuses: [], entities: [], raw_data: "{}", error: nil, issues: []
  }.freeze

  test "user opens workbench, runs whois, sees streaming result" do
    RdapChecker.stub(:check, RDAP_RESULT) do
      visit root_path

      assert_text "Ready."
      assert_selector "[data-mode-badge]", text: "NORMAL"

      # Switch to whois via rail
      first(".rail-item[data-tool-key='whois_lookup']").click

      # Type target and run
      fill_in "tool_run[domain]", with: "example.com"
      find("button[type=submit]", text: /RUN/).click

      # Result begins streaming
      assert_text "running", wait: 5
      # Wait for completion
      assert_text "done", wait: 30
      # Typing the target switched us to INSERT; the modal contract is "only Esc
      # returns to NORMAL" (mode_controller.js) — a run does not reset the mode.
      # Verify INSERT, then that Esc recovery still works after a run.
      assert_selector "[data-mode-badge]", text: "INSERT"
      find("body").send_keys(:escape)
      assert_selector "[data-mode-badge]", text: "NORMAL"
    end
  end

  test "email header analyzer renders a textarea primary input" do
    visit workbench_path(tool: "email_header_analyzer")
    assert_selector "textarea[name='tool_run[headers]']"
  end

  test "email header analyzer: paste headers -> rendered delivery path & auth" do
    headers = Rails.root.join("test/fixtures/files/email_headers/gmail.txt").read
    visit workbench_path(tool: "email_header_analyzer")
    fill_in "tool_run[headers]", with: headers
    click_button "RUN"
    assert_text "[DELIVERY PATH]", wait: 15
    assert_text "[AUTH RESULTS]"
    assert_text "203.0.113.5" # originating IP rendered (parse-derived, no network needed)
  end

  test "email header analyzer: spoofed message surfaces severity-tagged findings" do
    headers = Rails.root.join("test/fixtures/files/email_headers/spoofed.txt").read
    visit workbench_path(tool: "email_header_analyzer")
    fill_in "tool_run[headers]", with: headers
    click_button "RUN"
    # Findings block + the critical spoofing verdict are parse-derived (no network).
    assert_text "[FINDINGS]", wait: 15
    assert_text "Possible spoofing"
    assert_text "DMARC failed at the receiving server"
  end
end
