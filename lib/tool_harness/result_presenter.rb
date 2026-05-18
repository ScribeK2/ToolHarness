module ToolHarness
  class ResultPresenter
    Section = Struct.new(:title, :kvs, :issues, :raw, keyword_init: true) do
      def initialize(title:, kvs: {}, issues: [], raw: false)
        super
      end
    end

    def initialize(tool_run)
      @run = tool_run
    end

    def sections
      return [error_section] if @run.status == "failed"

      data = data_sections
      return [] if data.empty? && raw_issues.empty?

      data + (needs_issues_section? ? [issues_section] : [])
    end

    private

    def data_sections
      (@run.result_data || {}).reject { |_, v| v.blank? }.map do |key, value|
        case value
        when Hash
          Section.new(title: titleize(key), kvs: stringify(value))
        when Array
          Section.new(title: titleize(key), kvs: array_to_kvs(value))
        else
          Section.new(title: titleize(key), kvs: { key.to_s => value.to_s })
        end
      end
    end

    def needs_issues_section?
      return true if raw_issues.any?
      (@run.result_data || {}).values.any? { |v| !v.is_a?(Hash) }
    end

    def raw_issues
      @run.issues || []
    end

    def issues_section
      issues = (@run.issues || []).map { |i| i.is_a?(Hash) ? i : i.to_h }
      if issues.empty?
        Section.new(title: "Issues", kvs: { "" => "no issues found." })
      else
        Section.new(title: "Issues", issues: issues)
      end
    end

    def error_section
      Section.new(title: "Error", kvs: { "message" => (@run.error || "unknown error") })
    end

    def stringify(hash)
      hash.transform_values { |v| v.to_s }
    end

    def array_to_kvs(array)
      array.each_with_index.to_h { |item, i| ["[#{i}]", item.to_s] }
    end

    def titleize(key)
      key.to_s.split(/[_\-]/).map(&:capitalize).join(" ")
    end
  end
end
