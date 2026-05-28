require "test_helper"

class DnsPropagationSourceRegressionTest < ActiveSupport::TestCase
  FILES = %w[
    app/services/tools/dns_propagation.rb
    app/services/propagation_checker.rb
  ].freeze

  FILES.each do |relpath|
    test "#{relpath} does not shell out" do
      src = File.read(Rails.root.join(relpath))
      refute_match(/Open3/,             src, "#{relpath} must not use Open3")
      refute_match(/\bsystem\s*\(/,     src, "#{relpath} must not call system(")
      refute_match(/`[^`\n]*`/m,        src, "#{relpath} must not use backtick shellout")
    end
  end
end
