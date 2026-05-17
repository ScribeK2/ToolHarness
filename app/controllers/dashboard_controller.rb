class DashboardController < ApplicationController
  RECENT_LIMIT     = 8
  EXPIRY_THRESHOLD = 90  # days
  EXPIRY_LIMIT     = 5

  def index
    @recent_runs       = current_user.tool_runs.recent.limit(RECENT_LIMIT)
    @stats             = compute_stats
    @expiring_domains  = expiring_domains
    @expiring_certs    = expiring_certs
  end

  private

  def compute_stats
    runs = current_user.tool_runs
    completed = runs.where(status: "completed")

    critical = warning = info = 0
    completed.find_each do |run|
      (run.issues || []).each do |issue|
        severity = (issue["severity"] || issue[:severity]).to_s
        case severity
        when "critical" then critical += 1
        when "warning"  then warning  += 1
        when "info"     then info     += 1
        end
      end
    end

    total            = runs.count
    success_count    = runs.where(success: true).count
    success_rate_pct = total.positive? ? ((success_count.to_f / total) * 100).round : nil

    {
      total_runs:    total,
      successful:    success_count,
      success_rate:  success_rate_pct,
      critical:      critical,
      warning:       warning,
      info:          info
    }
  end

  # SSL Inspect runs whose certificate.days_until_expiry is within EXPIRY_THRESHOLD days.
  def expiring_certs
    list = []
    current_user.tool_runs
      .for_tool("ssl_inspect")
      .successful
      .find_each do |run|
        cert = run.result_data&.dig("certificate")
        next unless cert
        days = cert["days_until_expiry"]
        next unless days.is_a?(Numeric) && days >= 0 && days <= EXPIRY_THRESHOLD

        list << {
          target:     run.input_summary,
          days_until: days.to_i,
          run:        run
        }
      end
    list.sort_by { |e| e[:days_until] }.first(EXPIRY_LIMIT)
  end

  # WHOIS runs whose result_data.expiration_date parses to a date within EXPIRY_THRESHOLD.
  def expiring_domains
    list = []
    current_user.tool_runs
      .for_tool("whois_lookup")
      .successful
      .find_each do |run|
        date_str = run.result_data&.dig("expiration_date")
        next if date_str.blank?

        days = days_until(date_str)
        next unless days && days >= 0 && days <= EXPIRY_THRESHOLD

        list << {
          target:     run.input_summary,
          days_until: days,
          expiry:     date_str[0, 10],
          run:        run
        }
      end
    list.sort_by { |e| e[:days_until] }.first(EXPIRY_LIMIT)
  end

  def days_until(date_str)
    (Date.parse(date_str.to_s) - Date.today).to_i
  rescue ArgumentError, TypeError
    nil
  end
end
