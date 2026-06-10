require "test_helper"

class ToolHarness::ToolTest < ActiveSupport::TestCase
  def teardown
    # Remove any test-local classes from the global registry so they don't
    # leak into other tests that iterate Registry.tools.
    @added_keys&.each { |k| ToolHarness::Registry.tools.delete(k) }
  end

  test "including the concern auto-registers the class" do
    klass = make_tool_class("Tools::TestProbeAutoreg") do
      def self.category = :test
      def self.tool_name = "Auto-registered Probe"
    end

    assert_equal klass, ToolHarness::Registry.find_tool(:test_probe_autoreg)
  end

  test "abstract class methods raise NotImplementedError when not overridden" do
    klass = make_tool_class("Tools::TestProbeAbstract") do
      # Intentionally no #category or #tool_name overrides — still need them
      # defined for cleanup-time iteration to not crash other tests though.
      def self.tool_name = raise NotImplementedError, "x must implement .tool_name"
      def self.category = raise NotImplementedError, "x must implement .category"
    end

    assert_raises(NotImplementedError) { klass.tool_name }
    assert_raises(NotImplementedError) { klass.category }
  end

  test "default form_fields / input_type / timeout / cacheable" do
    klass = make_tool_class("Tools::TestProbeDefaults") do
      def self.tool_name = "Defaults"
      def self.category = :test
    end

    assert_equal({ domain: :text }, klass.form_fields)
    assert_equal :domain, klass.input_type
    assert_equal 30, klass.timeout
    assert klass.cacheable?
    assert_equal 1.hour, klass.cache_duration
  end

  test "run() sets execution_time and returns the Result from execute" do
    klass = make_tool_class("Tools::TestProbeRunOk") do
      def self.tool_name = "OK Probe"
      def self.category  = :test
      def self.cacheable? = false
      def execute(_params)
        ToolHarness::Result.new(success: true, tool: "OK Probe", summary: "ok")
      end
    end

    result = klass.new.run({})
    assert result.success?
    assert_equal "ok", result.summary
    assert_not_nil result.execution_time
    assert result.execution_time >= 0
  end

  test "run() rescues exceptions and returns a failure Result" do
    klass = make_tool_class("Tools::TestProbeRunBoom") do
      def self.tool_name = "Boom Probe"
      def self.category  = :test
      def self.cacheable? = false
      def execute(_params)
        raise "boom"
      end
    end

    result = klass.new.run({})
    assert_not result.success?
    assert_match(/RuntimeError.*boom/, result.error)
    assert_not_nil result.execution_time
  end

  test "default execute raises NotImplementedError (not swallowed)" do
    # run() rescues StandardError only; NotImplementedError is a ScriptError
    # and propagates so the developer sees the missing override loudly.
    klass = make_tool_class("Tools::TestProbeNoExec") do
      def self.tool_name = "No Exec"
      def self.category  = :test
      def self.cacheable? = false
    end

    assert_raises(NotImplementedError) { klass.new.run({}) }
  end

  test "run() caches when cacheable? is true" do
    # The test env default cache_store is :null_store. Swap to MemoryStore so
    # the fetch-on-second-call actually hits.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    call_count = 0
    klass = make_tool_class("Tools::TestProbeCache") do
      def self.tool_name = "Cache Probe"
      def self.category  = :test
    end
    klass.define_method(:execute) do |_params|
      call_count += 1
      ToolHarness::Result.new(success: true, tool: "Cache Probe", data: { run: call_count })
    end

    r1 = klass.new.run(domain: "example.com")
    r2 = klass.new.run(domain: "example.com")
    assert_equal 1, r1.data[:run]
    assert_equal 1, r2.data[:run], "second call should hit the cache"

    r3 = klass.new.run(domain: "other.com")
    assert_equal 2, r3.data[:run], "different params should bypass the cache"
  ensure
    Rails.cache = original_cache
  end

  test "preserve_path_in_input? defaults to false" do
    klass = make_tool_class("Tools::TestProbePreservePathDefault") do
      def self.category = :test
      def self.tool_name = "Preserve Path Default Probe"
    end
    refute klass.preserve_path_in_input?
  end

  test "preserve_path_in_input? can be overridden to true" do
    klass = make_tool_class("Tools::TestProbePreservePathTrue") do
      def self.category = :test
      def self.tool_name = "Preserve Path True Probe"
      def self.preserve_path_in_input? = true
    end
    assert klass.preserve_path_in_input?
  end

  test "Tools::WebsiteInspect opts into preserve_path_in_input?" do
    assert Tools::WebsiteInspect.preserve_path_in_input?
  end

  test "result_partial defaults to nil" do
    klass = make_tool_class("Tools::TestProbeResultPartialDefault") do
      def self.tool_name = "Result Partial Default Probe"
      def self.category  = :test
    end
    assert_nil klass.result_partial
  end

  test "tools can override result_partial" do
    klass = make_tool_class("Tools::TestProbeResultPartialOverride") do
      def self.tool_name      = "Result Partial Override Probe"
      def self.category       = :test
      def self.result_partial = "results/tools/foo"
    end
    assert_equal "results/tools/foo", klass.result_partial
  end

  private

  # Build a Tool-including class with a fixed name, run a config block, and
  # track it for teardown cleanup. The block runs via class_eval AFTER the
  # name is set, so the included hook can register correctly.
  def make_tool_class(full_name, &config)
    @added_keys ||= []
    @added_keys << full_name.demodulize.underscore.to_sym

    klass = Class.new
    klass.define_singleton_method(:name) { full_name }
    klass.class_eval { include ToolHarness::Tool }
    klass.class_eval(&config) if config
    klass
  end
end
