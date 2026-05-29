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
end
