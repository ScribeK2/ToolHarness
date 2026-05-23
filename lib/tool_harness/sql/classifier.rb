module ToolHarness
  module Sql
    class Classifier
      READ_KEYWORDS  = %w[SELECT SHOW EXPLAIN DESC DESCRIBE USE].freeze
      WRITE_SAFE_KEYWORDS = %w[INSERT REPLACE].freeze
      WRITE_REQUIRES_WHERE = %w[UPDATE DELETE].freeze
      DANGEROUS_KEYWORDS = %w[DROP TRUNCATE ALTER RENAME GRANT REVOKE CALL LOAD].freeze

      def self.classify(sql)
        sanitized = strip_comments_and_strings(sql.to_s)
        return :unknown if sanitized.strip.empty?
        return :unknown if multi_statement?(sanitized)

        first = leading_keyword(sanitized)
        return :unknown if first.nil?

        if first == "WITH"
          # Find the keyword that follows the (possibly nested) CTE list.
          after_cte = sanitized.sub(/\AWITH\s+.*?\)\s*/im, "")
          first = leading_keyword(after_cte) || "WITH"
        end

        case first
        when *READ_KEYWORDS                                       then :read
        when *WRITE_SAFE_KEYWORDS                                 then :write_safe
        when *WRITE_REQUIRES_WHERE
          has_where?(sanitized) ? :write_safe : :write_dangerous
        when *DANGEROUS_KEYWORDS                                  then :write_dangerous
        else
          :unknown
        end
      end

      def self.strip_comments_and_strings(sql)
        # Remove /* … */ block comments (non-greedy, multiline).
        s = sql.gsub(%r{/\*.*?\*/}m, " ")
        # Remove -- … and # … line comments to end of line.
        s = s.gsub(/--[^\n]*/, " ").gsub(/#[^\n]*/, " ")
        # Remove '…' and "…" string literals (handle simple backslash escapes).
        s = s.gsub(/'(?:\\.|[^'\\])*'/, "''").gsub(/"(?:\\.|[^"\\])*"/, '""')
        s
      end

      def self.leading_keyword(sanitized)
        m = sanitized.lstrip.match(/\A([A-Za-z_]+)/)
        m && m[1].upcase
      end

      def self.has_where?(sanitized)
        sanitized.match?(/\bWHERE\b/i)
      end

      def self.multi_statement?(sanitized)
        # Count semicolons that aren't at the very end (or followed only by whitespace).
        sanitized.sub(/;\s*\z/, "").include?(";")
      end
    end
  end
end
