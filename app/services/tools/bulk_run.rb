module Tools
  class BulkRun
    include ToolHarness::Tool

    MAX_DOMAINS = 50
    DOMAIN_REGEX = /\A[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?)+\z/

    def self.tool_name = "Bulk Domain Runner"
    def self.category = :diagnostics
    def self.description = "Runs a chosen domain-input tool against up to #{MAX_DOMAINS} domains sequentially and aggregates the per-domain results into one report. Useful for sweeping a list of customer domains through DNS, SSL, or email-auth checks."
    def self.input_type = :bulk
    def self.cacheable? = false
    def self.timeout = 600

    def self.form_fields
      selectable = ToolHarness::Registry.tools
        .reject { |key, _| key == :bulk_run }
        .select { |_, klass| klass.form_fields.key?(:domain) }
        .map    { |key, klass| [klass.tool_name, key.to_s] }
        .sort_by(&:first)

      {
        domains: {
          type: :textarea,
          label: "Domains (one per line, comma, or whitespace separated — max #{MAX_DOMAINS})",
          rows: 8,
          placeholder: "example.com\nanother.com\nthird.org"
        },
        tool_key: {
          type:    :select,
          label:   "Tool to run on each domain",
          options: selectable
        }
      }
    end

    def execute(params)
      raw_domains  = params[:domains].to_s
      tool_key_str = params[:tool_key].to_s.strip

      domains   = parse_domains(raw_domains)
      truncated = domains.size > MAX_DOMAINS
      domains   = domains.first(MAX_DOMAINS)

      return invalid("No valid domains provided") if domains.empty?

      tool_class = ToolHarness::Registry.find_tool(tool_key_str)
      return invalid("Unknown tool: #{tool_key_str}") unless tool_class
      return invalid("Tool #{tool_key_str} does not accept a domain input") unless tool_class.form_fields.key?(:domain)

      runs = domains.map do |domain|
        inner = safely_run(tool_class, domain)
        {
          domain:          domain,
          success:         inner.success?,
          summary:         inner.summary,
          issue_count:     inner.issues.size,
          critical_count:  count_severity(inner.issues, "critical"),
          warning_count:   count_severity(inner.issues, "warning"),
          execution_time:  inner.execution_time&.round(3),
          error:           inner.error
        }
      end

      success_count = runs.count { |r| r[:success] }
      failure_count = runs.size - success_count
      total_issues  = runs.sum { |r| r[:issue_count] }
      total_critical = runs.sum { |r| r[:critical_count] }

      ToolHarness::Result.new(
        success: success_count.positive?,
        tool: self.class.tool_name,
        data: {
          tool_name:      tool_class.tool_name,
          tool_key:       tool_key_str,
          domain_count:   domains.size,
          success_count:  success_count,
          failure_count:  failure_count,
          total_issues:   total_issues,
          total_critical: total_critical,
          truncated:      truncated,
          runs:           runs
        },
        issues:  build_issues(runs, truncated),
        summary: build_summary(tool_class, runs, success_count, failure_count)
      )
    end

    private

    def parse_domains(raw)
      raw.split(/[\s,;]+/)
        .map(&:strip)
        .reject(&:empty?)
        .uniq
        .select { |d| d.size <= 253 && d.match?(DOMAIN_REGEX) }
    end

    def safely_run(tool_class, domain)
      tool_class.new.run(domain: domain)
    rescue StandardError => e
      ToolHarness::Result.new(
        success: false,
        tool: tool_class.tool_name,
        error: "#{e.class}: #{e.message}",
        summary: "Inner run crashed"
      )
    end

    def count_severity(issues, severity)
      issues.count { |i| (i["severity"] || i[:severity]).to_s == severity }
    end

    def invalid(message)
      ToolHarness::Result.new(
        success: false,
        tool: self.class.tool_name,
        error: message,
        summary: message
      )
    end

    def build_issues(runs, truncated)
      issues = []

      if truncated
        issues << {
          severity: "warning",
          code: "input_truncated",
          title: "Input list truncated",
          message: "Submitted list exceeded the #{MAX_DOMAINS}-domain cap; only the first #{MAX_DOMAINS} were run.",
          recommendation: "Split the list into multiple bulk runs."
        }
      end

      failures = runs.count { |r| !r[:success] }
      if failures == runs.size
        issues << {
          severity: "critical",
          code: "all_runs_failed",
          title: "All runs failed",
          message: "None of the #{runs.size} domains produced a successful result.",
          recommendation: "Check the selected tool and the input list for systemic issues (e.g., DNS, network, target reachability)."
        }
      elsif failures.positive? && failures >= (runs.size / 2.0).ceil
        issues << {
          severity: "warning",
          code: "majority_failed",
          title: "Majority of runs failed",
          message: "#{failures} of #{runs.size} runs failed.",
          recommendation: "Inspect the per-domain results below for the common failure mode."
        }
      end

      issues
    end

    def build_summary(tool_class, runs, success_count, failure_count)
      "Ran #{tool_class.tool_name} on #{runs.size} domain#{'s' unless runs.size == 1}: " \
        "#{success_count} OK, #{failure_count} failed."
    end
  end
end
