require_relative "classifier"

module ToolHarness
  module Sql
    class LimitInjector
      # Returns { sql: String, injected: Boolean }.
      # Appends LIMIT <n> to plain SELECTs (or CTE-then-SELECT) that don't
      # already have a LIMIT clause. Leaves everything else untouched.
      def self.append(sql, limit)
        return { sql: sql, injected: false } unless select_like?(sql)
        return { sql: sql, injected: false } if has_limit?(sql)

        # Preserve a single trailing semicolon if present.
        trimmed = sql.sub(/\s*;\s*\z/, "")
        suffix  = sql.match?(/;\s*\z/) ? ";" : ""
        { sql: "#{trimmed} LIMIT #{limit.to_i}#{suffix}", injected: true }
      end

      def self.select_like?(sql)
        sanitized = Classifier.strip_comments_and_strings(sql)
        head = Classifier.leading_keyword(sanitized)
        return false if head.nil?
        return true  if head == "SELECT"
        return true  if head == "WITH" && Classifier.classify(sql) == :read
        false
      end

      def self.has_limit?(sql)
        sanitized = Classifier.strip_comments_and_strings(sql)
        sanitized.match?(/\bLIMIT\b/i)
      end
    end
  end
end
