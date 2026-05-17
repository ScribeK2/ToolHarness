class CommandsController < ApplicationController
  def create
    cmd = ToolHarness::CommandDispatcher.parse(params[:cmd].to_s)

    stream =
      case cmd.name
      when :run     then dispatch_run(cmd.args)
      when :export  then dispatch_export(cmd.args, params[:run_id])
      when :purge   then dispatch_purge(cmd.args)
      when :unknown then error_stream("no command '#{cmd.args[:raw]}'")
      when :empty   then error_stream("empty command")
      else
        error_stream("'#{cmd.name}' is client-side; should not have been POSTed")
      end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream }
    end
  end

  private

  def dispatch_run(args)
    tool_class = ToolHarness::Registry.find_tool(args[:tool])
    return error_stream("unknown tool '#{args[:tool]}'") unless tool_class

    run = ToolRun.create_pending!(
      user: current_user,
      tool_class: tool_class,
      params: { tool_class.form_fields.keys.first => args[:target] }
    )
    ToolRunJob.perform_later(run.id)

    turbo_stream.replace(
      "result_panel",
      partial: "workbench/result_panel_with_run",
      locals: { tool_run: run }
    )
  end

  def dispatch_export(args, run_id)
    run = current_user.tool_runs.find_by(id: run_id)
    return error_stream("no current run to export") unless run

    payload = case args[:format]
              when "csv"  then to_csv(run)
              when "md"   then to_md(run)
              else             JSON.pretty_generate(run.as_json)
              end
    filename = "toolrun-#{run.id}.#{args[:format] == 'md' ? 'md' : args[:format]}"
    data_url = "data:text/plain;charset=utf-8,#{ERB::Util.url_encode(payload)}"

    turbo_stream.replace(
      "cmdline_message",
      "<div id='cmdline_message' class='px-3 py-1 text-cyan text-xs'>".html_safe +
        ActionController::Base.helpers.link_to("download #{filename}", data_url, download: filename, class: "underline") +
        "</div>".html_safe
    )
  end

  def dispatch_purge(args)
    older = args[:older].to_s
    return error_stream("usage: :purge older=<N>d") unless older =~ /\A(\d+)d\z/
    days = older.sub(/d\z/, "").to_i
    n = current_user.tool_runs.purge_older_than!(days.days)
    turbo_stream.replace(
      "cmdline_message",
      "<div id='cmdline_message' class='px-3 py-1 text-cyan text-xs'>▸ purged #{n} runs older than #{days}d</div>".html_safe
    )
  end

  def error_stream(msg)
    turbo_stream.replace(
      "cmdline_message",
      "<div id='cmdline_message' class='px-3 py-1 text-red text-xs'>#{msg}</div>".html_safe
    )
  end

  def to_csv(run)
    lines = ["key,value"]
    (run.result_data || {}).each { |k, v| lines << "#{k},\"#{v.to_s.gsub('"', '""')}\"" }
    lines.join("\n")
  end

  def to_md(run)
    lines = ["# #{run.tool_name} — #{run.input_summary}", ""]
    (run.result_data || {}).each { |k, v| lines << "- **#{k}**: #{v}" }
    lines.join("\n")
  end

  def turbo_stream
    Turbo::Streams::TagBuilder.new(view_context)
  end
end
