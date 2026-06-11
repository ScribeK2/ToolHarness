module ToolHarness
  # Renders ResultPresenter sections as ticket-ready plain text — the
  # "copy full" counterpart of the HTML section partials. Pure: no view
  # or DB access, fully driven by the Section structs passed in.
  class SectionTextRenderer
    def initialize(sections)
      @sections = sections
    end

    def to_text
      @sections.filter_map { |s| render_section(s) }.join("\n\n")
    end

    private

    def render_section(section)
      body =
        if section.table
          render_table(section.table)
        elsif section.issues.present?
          render_issues(section.issues)
        elsif section.kvs.present?
          render_kvs(section.kvs)
        end
      return nil if body.blank?

      "## #{section.title}\n#{body}"
    end

    def render_kvs(kvs)
      # matches ResultPresenter#array_to_kvs index keys ("[0]", "[1]", …)
      if kvs.keys.all? { |k| k.to_s.match?(/\A\[\d+\]\z/) }
        return kvs.values.map(&:to_s).join("\n")
      end

      width = kvs.keys.map { |k| k.to_s.length }.max
      kvs.map { |k, v| render_kv(k.to_s, v.to_s, width) }.join("\n")
end

    def render_kv(key, value, width)
      prefix = key.empty? ? "" : "#{key}:".ljust(width + 3)
      indent = " " * prefix.length
      first, *rest = value.split("\n", -1)
      ([prefix + first.to_s] + rest.map { |l| indent + l }).map(&:rstrip).join("\n")
end

    def render_table(table)
      widths = table.columns.to_h do |c|
        [c.key, ([c.label.length] + table.rows.map { |r| r[c.key].to_s.length }).max]
      end
      header = row_line(table.columns, widths) { |c| c.label }
      lines  = table.rows.map { |row| row_line(table.columns, widths) { |c| row[c.key].to_s } }
      ([header] + lines).join("\n")
    end

    def row_line(columns, widths)
      columns.map do |c|
        cell = yield(c)
        c.numeric ? cell.rjust(widths[c.key]) : cell.ljust(widths[c.key])
      end.join("  ").rstrip
end

    def render_issues(issues)
      issues.map do |issue|
        i = issue.transform_keys(&:to_s)
        line = "- [#{(i["severity"] || "info").upcase}] #{i["title"]}"
        line << ": #{i["message"]}" if i["message"].present?
        line
      end.join("\n")
end
  end
end
