require "test_helper"

class Investigations::CorrelationResultTest < ActiveSupport::TestCase
  test "holds verdict, findings, suggested_track" do
    r = Investigations::CorrelationResult.new(
      verdict_status: "issues",
      findings: [{ "code" => "x" }],
      suggested_track: "email_delivery"
    )
    assert_equal "issues", r.verdict_status
    assert_equal [{ "code" => "x" }], r.findings
    assert_equal "email_delivery", r.suggested_track
  end
end
