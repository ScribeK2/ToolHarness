require "test_helper"

class WhoisCheckerTest < ActiveSupport::TestCase
  test "does not shell out to system whois" do
    # AppImage rule: tools must not depend on host binaries.
    # Source-inspection enforces "no shell-outs in this file".
    src = File.read(Rails.root.join("app/services/whois_checker.rb"))
    refute_match(/\bsystem\s*\(/, src, "WhoisChecker must not call system()")
    refute_match(/`[^`]*whois[^`]*`/, src, "WhoisChecker must not backtick-shell to whois")
    refute_match(/Open3/, src, "WhoisChecker must not use Open3 to shell out")
  end
end
