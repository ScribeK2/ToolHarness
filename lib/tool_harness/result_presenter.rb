module ToolHarness
  class ResultPresenter
    Section = Struct.new(:title, :kvs, :issues, :raw, :table, keyword_init: true) do
      def initialize(title:, kvs: {}, issues: [], raw: false, table: nil)
        super
      end
    end

    Table  = Struct.new(:columns, :rows, keyword_init: true)
    Column = Struct.new(:key, :label, :numeric, keyword_init: true)

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
          if tabular?(value)
            Section.new(title: titleize(key), table: build_table(value))
          else
            Section.new(title: titleize(key), kvs: array_to_kvs(value))
          end
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

    def tabular?(value)
      value.any? && value.all? { |e| e.is_a?(Hash) }
    end

    def build_table(rows)
      keys = rows.flat_map(&:keys).uniq
      columns = keys.map do |k|
        Column.new(key: k.to_s, label: titleize(k), numeric: numeric_column?(rows, k))
      end
      formatted = rows.map do |row|
        keys.each_with_object({}) { |k, h| h[k.to_s] = format_cell(row[k]) }
      end
      Table.new(columns: columns, rows: formatted)
    end

    def numeric_column?(rows, key)
      vals = rows.map { |r| r[key] }.reject { |v| v.nil? || v.to_s.strip.empty? }
      vals.any? && vals.all? do |v|
        !v.is_a?(Array) && !v.is_a?(Hash) && !Float(v.to_s, exception: false).nil?
      end
    end

    def format_cell(value)
      case value
      when nil   then "—"
      when Array then value.map(&:to_s).join(", ")
      when Hash  then value.map { |k, v| "#{k}=#{v}" }.join(", ")
      else            value.to_s
      end
    end

    def titleize(key)
      key.to_s.split(/[_\-]/).map(&:capitalize).join(" ")
    end
  end
end
