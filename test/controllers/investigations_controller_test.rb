require "test_helper"

class InvestigationsControllerTest < ActionDispatch::IntegrationTest
  test "POST create starts an investigation and three child runs, then redirects to show" do
    inv = nil
    assert_difference -> { Investigation.count }, 1 do
      assert_difference -> { ToolRun.count }, 3 do
        post investigations_path, params: { domain: "example.com", track: "orientation" }
      end
    end
    inv = Investigation.order(created_at: :desc).first
    assert_equal "example.com", inv.domain
    assert_redirected_to investigation_path(inv)
  end

  test "POST create normalizes the domain (strips scheme/path)" do
    post investigations_path, params: { domain: "https://example.com/foo" }
    assert_equal "example.com", Investigation.order(created_at: :desc).first.domain
  end

  test "GET show renders the surface with the step list and verdict region" do
    inv = Investigations::Orchestrator.start(domain: "example.com")
    get investigation_path(inv)
    assert_response :success
    assert_select "#investigation_steps_#{inv.id}"
    assert_select "#investigation_verdict_#{inv.id}"
    assert_match(/whois lookup/i, response.body)
  end

  test "GET show on a running investigation shows 'report pending', not a copy button" do
    inv = Investigations::Orchestrator.start(domain: "example.com")  # children stay pending -> running
    get investigation_path(inv)
    assert_response :success
    assert_select "#investigation_report_#{inv.id}"
    assert_match(/report pending/i, response.body)
    assert_no_match(/copy report/i, response.body)
  end

  test "GET show on a completed investigation shows the copy-report button" do
    inv = Investigation.create!(domain: "example.com", track: "orientation", status: "completed",
                                verdict_status: "healthy", completed_at: Time.current, findings: [])
    inv.tool_runs.create!(tool_key: "whois_lookup", tool_name: "WHOIS Lookup", category: "domain",
                          status: "completed", success: true, step_order: 0, summary: "ok")
    get investigation_path(inv)
    assert_response :success
    assert_select "#investigation_report_#{inv.id}"
    assert_match(/copy report/i, response.body)
  end

  test "create with an unknown track returns 422 and creates nothing" do
    assert_no_difference -> { Investigation.count } do
      post investigations_path, params: { domain: "example.com", track: "bogus" }
    end
    assert_response :unprocessable_entity
  end

  test "create with the email_delivery track starts an email investigation" do
    assert_difference -> { Investigation.count }, 1 do
      post investigations_path, params: { domain: "example.com", track: "email_delivery" }
    end
    assert_equal "email_delivery", Investigation.last.track
  end

  test "show renders the skipped glyph and reason for a skipped step" do
    inv = Investigation.create!(domain: "example.com", track: "email_delivery", status: "completed",
                                started_at: 1.minute.ago, completed_at: Time.current,
                                verdict_status: "critical", findings: [])
    inv.tool_runs.create!(tool_key: "blacklist", tool_name: "Blacklist Check", category: "diagnostics",
                          status: "skipped", skip_reason: "No MX records — reputation check skipped", step_order: 5)

    get investigation_path(inv)
    assert_response :success
    assert_match "⊝", @response.body
    assert_match "No MX records", @response.body
  end

  test "show renders a live next-track button when the suggested track exists" do
    inv = Investigation.create!(domain: "example.com", track: "orientation", status: "completed",
                                started_at: 1.minute.ago, completed_at: Time.current,
                                verdict_status: "issues", suggested_track: "email_delivery",
                                findings: [{ "severity" => "warning", "code" => "x", "title" => "t", "message" => "m" }])
    inv.tool_runs.create!(tool_key: "dns_lookup", tool_name: "DNS", category: "dns", status: "completed", success: true, step_order: 0)

    get investigation_path(inv)
    assert_response :success
    assert_select "form[action=?]", investigations_path  # button_to renders a form posting to /investigations
    assert_match "investigate EMAIL DELIVERY", @response.body
  end
end
