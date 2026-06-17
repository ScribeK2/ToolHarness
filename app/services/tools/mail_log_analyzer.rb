module Tools
  class MailLogAnalyzer
    include ToolHarness::Tool

    def self.tool_name = "Mail Log Analyzer"
    def self.category  = :email
    def self.description = "Paste Postfix/Dovecot delivery log lines from Graylog to reconstruct each message's delivery path by queue id — sender, recipients, relay, and the receiving server's actual SMTP verdict (delivered / deferred / bounced / rejected) with the reason decoded into plain English."
    def self.form_fields = { log: :textarea }
    def self.input_type  = :email
    def self.cacheable?  = false
    def self.timeout     = 20
    def self.result_partial = "results/tools/mail_log_analyzer"

    def execute(params)
      parsed = MailLogParser.new(params[:log].to_s).analyze

      unless parsed[:ok]
        return ToolHarness::Result.new(
          success: false, tool: self.class.tool_name,
          error: "No mail delivery log lines detected.",
          summary: "Paste Postfix/Dovecot log lines (queue-id, status=…) copied from Graylog."
        )
      end

      ToolHarness::Result.new(
        success: true,
        tool: self.class.tool_name,
        data: {
          messages:       parsed[:messages],
          rejections:     parsed[:rejections],
          unparsed_count: parsed[:unparsed_count]
        },
        issues:  build_issues(parsed),
        summary: build_summary(parsed)
      )
    end

    private

    def build_issues(parsed)
      issues = []

      parsed[:messages].each do |m|
        qid = m[:queue_id]
        case m[:verdict]
        when "BOUNCED"
          bounced = m[:recipients].select { |r| r[:status] == "bounced" }
          all_bounced = m[:recipients].any? && m[:recipients].all? { |r| r[:status] == "bounced" }
          reason = bounced.first&.dig(:reason) || bounced.first&.dig(:reply)
          issues << {
            "severity" => all_bounced ? "critical" : "warning",
            "title"    => "Message #{qid} bounced",
            "message"  => "#{bounced.map { |r| r[:to] }.compact.join(', ')}: #{reason}."
          }
        when "DEFERRED"
          d = m[:recipients].find { |r| r[:status] == "deferred" }
          issues << {
            "severity" => "info",
            "title"    => "Message #{qid} deferred (will retry)",
            "message"  => "#{d&.dig(:to)}: #{d&.dig(:reason) || d&.dig(:reply)}."
          }
        when "INCOMPLETE"
          issues << {
            "severity" => "info",
            "title"    => "Message #{qid} has no final delivery status",
            "message"  => "No sent/deferred/bounced line for this queue id in the pasted window — the log may be truncated."
          }
        end
      end

      parsed[:rejections].each do |r|
        issues << {
          "severity" => "warning",
          "title"    => "Inbound from #{r[:client_host] || r[:client_ip]} rejected at our server",
          "message"  => "to #{r[:to]}: #{r[:reason] || r[:reply]}."
        }
      end

      issues
    end

    def build_summary(parsed)
      counts = Hash.new(0)
      parsed[:messages].each { |m| counts[m[:verdict]] += 1 }
      total = parsed[:messages].size

      parts = []
      parts << "#{counts['DELIVERED']} delivered" if counts["DELIVERED"] > 0
      parts << "#{counts['BOUNCED']} bounced"      if counts["BOUNCED"] > 0
      parts << "#{counts['DEFERRED']} deferred"    if counts["DEFERRED"] > 0
      parts << "#{counts['INCOMPLETE']} incomplete" if counts["INCOMPLETE"] > 0

      summary = "#{total} message#{'s' unless total == 1}"
      summary += ": #{parts.join(', ')}" unless parts.empty?
      summary += " · #{parsed[:rejections].size} rejected at edge" if parsed[:rejections].any?
      "#{summary}."
    end
  end
end
