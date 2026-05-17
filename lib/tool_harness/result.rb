module ToolHarness
  class Result
    attr_accessor :success, :tool, :data, :issues, :recommendations,
                  :summary, :error, :execution_time, :cached, :checked_at

    def initialize(success:, tool: nil, data: {}, issues: [], recommendations: [], summary: nil, error: nil, execution_time: nil)
      @success = success
      @tool = tool
      @data = data
      @issues = issues
      @recommendations = recommendations
      @summary = summary
      @error = error
      @execution_time = execution_time
      @cached = false
      @checked_at = Time.current.iso8601
    end

    def critical_issues
      issues.select { |i| i[:severity] == "critical" }
    end

    def warnings
      issues.select { |i| i[:severity] == "warning" }
    end

    def info_issues
      issues.select { |i| i[:severity] == "info" }
    end

    def has_issues?
      issues.any?
    end

    def success?
      !!success
    end

    def to_h
      {
        success: success,
        tool: tool,
        data: data,
        issues: issues,
        recommendations: recommendations,
        summary: summary,
        error: error,
        execution_time: execution_time,
        cached: cached,
        checked_at: checked_at
      }
    end

    def to_json(*)
      to_h.to_json(*)
    end
  end
end
