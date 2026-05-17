module ToolHarness
  class RunFilter
    TOKEN_RE = /\A([a-z_]+)(=|~|<|>=|>|<=)?(.+)?\z/i

    def self.apply(scope, query)
      tokens(query).each do |token|
        scope = apply_token(scope, token)
      end
      scope
    end

    def self.errors_for(query)
      tokens(query).reject { |t| recognized?(t) }.map { |t| "unrecognized: #{t[:raw]}" }
    end

    def self.tokens(query)
      query.to_s.split(/\s+/).reject(&:empty?).map do |raw|
        case raw
        when /\A(today|yesterday|\d+d)\z/i then { kind: :timeframe, value: raw.downcase, raw: raw }
        when TOKEN_RE                      then { kind: :kv, key: $1.downcase.to_sym, op: $2 || "=", val: $3.to_s, raw: raw }
        else                                    { kind: :unknown, raw: raw }
        end
      end
    end

    def self.recognized?(token)
      return true if token[:kind] == :timeframe
      return false if token[:kind] == :unknown
      %i[tool target status severity expires age].include?(token[:key])
    end

    def self.apply_token(scope, token)
      case token[:kind]
      when :timeframe then apply_timeframe(scope, token[:value])
      when :kv        then apply_kv(scope, token)
      else                 scope
      end
    end

    def self.apply_timeframe(scope, value)
      case value
      when "today"     then scope.where("created_at >= ?", Date.today.beginning_of_day)
      when "yesterday" then scope.where(created_at: Date.yesterday.beginning_of_day..Date.yesterday.end_of_day)
      when /\A(\d+)d\z/i then scope.where("created_at >= ?", $1.to_i.days.ago)
      else                  scope
      end
    end

    def self.apply_kv(scope, token)
      key, op, val = token[:key], token[:op], token[:val]
      case key
      when :tool     then scope.where(tool_key: val)
      when :target   then scope.where("input_summary LIKE ?", "%#{val.gsub('%', '\%')}%")
      when :status   then val == "err" ? scope.where(success: false) : scope.where(status: val)
      when :severity then apply_severity(scope, op, val)
      when :expires  then apply_expires(scope, op, val)
      when :age      then apply_age(scope, op, val)
      else                scope
      end
    end

    SEVERITY_RANK = { "info" => 0, "warn" => 1, "warning" => 1, "crit" => 2, "critical" => 2 }.freeze

    def self.apply_severity(scope, op, val)
      threshold = SEVERITY_RANK[val.downcase] || 0
      scope.select do |run|
        (run.issues || []).any? { |i| (SEVERITY_RANK[(i["severity"] || i[:severity]).to_s] || -1) >= threshold }
      end.then { |arr| filter_to_ids(scope, arr) }
    end

    def self.apply_expires(scope, op, val)
      days = val.to_s.sub(/d\z/, "").to_i
      scope.select do |run|
        d = expires_days(run)
        d && d >= 0 && (op == "<" ? d < days : op == "<=" ? d <= days : op == ">" ? d > days : op == ">=" ? d >= days : d == days)
      end.then { |arr| filter_to_ids(scope, arr) }
    end

    def self.expires_days(run)
      if run.tool_key == "whois_lookup"
        d = run.result_data&.dig("expiration_date")
        d ? (Date.parse(d) - Date.today).to_i : nil
      elsif run.tool_key == "ssl_inspect"
        cert = run.result_data&.dig("certificate")
        cert&.dig("days_until_expiry")&.to_i
      end
    rescue ArgumentError
      nil
    end

    def self.apply_age(scope, op, val)
      n = val.sub(/h\z/, "").to_i
      scope.where("created_at >= ?", n.hours.ago)
    end

    def self.filter_to_ids(scope, array)
      scope.where(id: array.map(&:id))
    end
  end
end
