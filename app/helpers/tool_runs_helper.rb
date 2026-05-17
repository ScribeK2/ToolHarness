module ToolRunsHelper
  # Ticket-ready, copy-paste formatted summary of a tool run.
  # Multi-line, plain text — no markdown.
  def tool_run_ticket_text(tool_run)
    lines = []
    header = "[#{tool_run.tool_name}]"
    header << " #{tool_run.input_summary}" if tool_run.input_summary.present?
    lines << header

    lines << tool_run.summary if tool_run.summary.present?

    case tool_run.status
    when "failed"
      lines << ""
      lines << "FAILED: #{tool_run.error}" if tool_run.error.present?
    when "completed"
      issues = tool_run.issues || []
      if issues.any?
        lines << ""
        lines << "Issues (#{issues.size}):"
        %w[critical warning info].each do |severity|
          issues.select { |i| (i["severity"] || i[:severity]).to_s == severity }.each do |issue|
            i = issue.with_indifferent_access
            lines << "  - [#{severity.upcase}] #{i[:title]}#{": #{i[:message]}" if i[:message].present?}"
          end
        end
      end
    end

    lines << ""
    footer = "Run ##{tool_run.id}"
    footer << " · #{tool_run.execution_time.round(3)}s" if tool_run.execution_time
    footer << " · #{tool_run.created_at.utc.strftime('%Y-%m-%d %H:%M UTC')}"
    lines << footer

    lines.join("\n")
  end
end
