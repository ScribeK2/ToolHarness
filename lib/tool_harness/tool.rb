module ToolHarness
  module Tool
    extend ActiveSupport::Concern

    included do
      ToolHarness::Registry.register_tool(self)
    end

    class_methods do
      def tool_name
        raise NotImplementedError, "#{name} must implement .tool_name"
      end

      def category
        raise NotImplementedError, "#{name} must implement .category"
      end

      def description
        ""
      end

      def form_fields
        { domain: :text }
      end

      def input_type
        :domain
      end

      def timeout
        30
      end

      def cacheable?
        true
      end

      def cache_duration
        1.hour
      end
    end

    def execute(params)
      raise NotImplementedError, "#{self.class.name} must implement #execute"
    end

    def run(params)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = if self.class.cacheable?
        cache_key = "tool_harness:#{self.class.name.demodulize.underscore}:#{params.sort_by { |k, _| k.to_s }.to_s}"
        Rails.cache.fetch(cache_key, expires_in: self.class.cache_duration) { execute(params) }
      else
        execute(params)
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      result.execution_time = elapsed
      result
    rescue StandardError => e
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      ToolHarness::Result.new(
        success: false,
        tool: self.class.tool_name,
        error: "#{e.class}: #{e.message}",
        execution_time: elapsed
      )
    end
  end
end
