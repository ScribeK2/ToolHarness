module ApplicationHelper
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

  # Tools the current run's target can be handed off to. Same input_type,
  # plus :domain targets may also target :host tools. Excludes the current
  # tool and special input types. Returns [tool_key, display_name] sorted.
  def sibling_tools_for(tool_run)
    tool_class = tool_run.tool_class
    return [] unless tool_class

    allowed = case tool_class.input_type
              when :domain then %i[domain host]
              when :host   then %i[host]
              else []
              end
    return [] if allowed.empty?

    current_key = tool_run.tool_key.to_sym
    ToolHarness::Registry.tools
      .reject { |key, _klass| key == current_key }
      .select { |_key, klass| allowed.include?(klass.input_type) }
      .map    { |key, klass| [key.to_s, klass.tool_name] }
      .sort_by { |_key, name| name }
  end
end
