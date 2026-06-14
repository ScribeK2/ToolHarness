require "test_helper"

class Tools::EmailHeaderAnalyzerTest < ActiveSupport::TestCase
  def fixture(name)
    Rails.root.join("test/fixtures/files/email_headers/#{name}").read
  end

  test "empty paste -> unsuccessful Result, no raise" do
    res = Tools::EmailHeaderAnalyzer.new.execute(headers: "   ")
    assert_not res.success
    assert_match(/no email headers/i, res.summary.to_s + res.error.to_s)
  end

  test "spoofed fixture -> critical spoofing issue and dmarc-fail issue, origin ip present" do
    res = Tools::EmailHeaderAnalyzer.new.execute(headers: fixture("spoofed.txt"))
    assert res.success
    titles = res.issues.map { |i| i["title"] }
    assert(titles.any? { |t| t =~ /dmarc/i }, "expected a dmarc issue, got: #{titles.inspect}")
    assert(titles.any? { |t| t =~ /spoof|alignment/i }, "expected a spoofing/alignment issue, got: #{titles.inspect}")
    assert_equal "198.51.100.66", res.data[:origin][:ip]
  end

  test "gmail fixture -> no critical issues, summary mentions pass" do
    res = Tools::EmailHeaderAnalyzer.new.execute(headers: fixture("gmail.txt"))
    assert res.success
    assert_empty res.critical_issues
    assert_match(/pass/i, res.summary)
  end
end
