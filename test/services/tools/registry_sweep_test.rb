require "test_helper"

# Sweeps every registered tool and verifies its public surface: required
# metadata, registry key, and (for tools with explicit input validation)
# that invalid input is rejected cleanly without raising.
class Tools::RegistrySweepTest < ActiveSupport::TestCase
  # All real tools should be present. If you add a new tool, add it here too —
  # the missing/extra diff in "every expected tool is registered" catches accidental registry drift.
  EXPECTED_TOOLS = %i[
    blacklist
    bulk_run
    credentials
    dns_lookup
    email_auth_check
    email_validity
    historical_dns
    hosting_diagnostic
    ipinfo
    page_speed
    sql_workbench
    ssl_inspect
    subdomain_scan
    website_inspect
    whois_lookup
  ].freeze

  # Tools that have an explicit input validator and return a Result instead
  # of raising or hitting the network. Used by the validation-rejection test.
  VALIDATED_TOOLS = {
    blacklist:          { domain: "; injection" },
    hosting_diagnostic: { domain: "; injection" },
    page_speed:         { domain: "" },
    historical_dns:     { domain: "" }
    # NB: bulk_run is now a custom-partial launcher (execute raises NotImplementedError,
    # managed via BatchesController) — excluded from VALIDATED_TOOLS, like sql_workbench.
  }.freeze

  test "every expected tool is registered" do
    registered = ToolHarness::Registry.tools.keys.sort
    expected   = EXPECTED_TOOLS.sort
    missing    = expected - registered
    extra      = registered - expected

    assert missing.empty?, "missing from registry: #{missing.inspect}"
    assert extra.empty?,   "unexpected extras in registry: #{extra.inspect}"
  end

  EXPECTED_TOOLS.each do |key|
    test "#{key} has valid metadata" do
      klass = ToolHarness::Registry.find_tool(key)
      assert klass, "tool #{key} not registered"

      assert_kind_of String, klass.tool_name
      assert klass.tool_name.length.positive?, "#{key}.tool_name is blank"

      assert_kind_of Symbol, klass.category
      assert klass.category.to_s.length.positive?, "#{key}.category is blank"

      assert_kind_of Hash,   klass.form_fields
      assert klass.form_fields.any?, "#{key}.form_fields is empty"

      assert_kind_of Symbol, klass.input_type
      assert [true, false].include?(klass.cacheable?), "#{key}.cacheable? must return a boolean"

      assert_equal key, klass.name.demodulize.underscore.to_sym,
        "#{key}: registry key should match underscored class name"
    end
  end

  VALIDATED_TOOLS.each do |key, bad_params|
    test "#{key} rejects invalid input without raising" do
      klass = ToolHarness::Registry.find_tool(key)
      result = nil

      assert_nothing_raised { result = klass.new.run(bad_params) }
      assert_kind_of ToolHarness::Result, result
      assert_not result.success?, "#{key} should report failure for invalid input #{bad_params.inspect}"
      assert result.error.present? || result.summary.to_s.match?(/invalid|missing|unknown|no valid/i),
        "#{key} should surface an error or descriptive summary; got error=#{result.error.inspect} summary=#{result.summary.inspect}"
    end
  end

  private

  def assert_nothing_raised
    yield
  rescue => e
    flunk "expected no exception, got #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
  end
end
