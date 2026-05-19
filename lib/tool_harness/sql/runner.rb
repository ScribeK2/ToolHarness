require_relative "classifier"
require_relative "limit_injector"
require_relative "result"

module ToolHarness
  module Sql
    class Runner
      RETRYABLE_CODES = [2006, 2013].freeze # MySQL server has gone away / lost connection during query

      def initialize(client:, profile_name:, database:, write_mode:, session_limit:, timeout:, confirmed: false)
        @client        = client
        @profile_name  = profile_name
        @database      = database
        @write_mode    = write_mode.to_sym
        @session_limit = session_limit.to_i
        @timeout       = timeout.to_i
        @confirmed     = !!confirmed
      end

      def execute(sql)
        klass = Classifier.classify(sql)

        gate_error = gate(klass)
        return gate_error if gate_error

        inject = LimitInjector.append(sql, @session_limit)
        final_sql = inject[:sql]

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw, retried = run_with_one_retry(final_sql)
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        if raw.is_a?(Result) # error path
          raw.time_ms = elapsed_ms
          return raw
        end

        normalize(raw, elapsed_ms, inject[:injected], klass)
      rescue StandardError => e
        Result.new(
          columns: [], rows: [], row_count: 0, time_ms: 0,
          applied_limit: nil, write_affected: nil,
          error_code: mysql_code(e), error_message: "#{e.class}: #{e.message}"
        )
      end

      def reconnect!
        # Overridden by the controller that owns the ConnectionStore; default noop.
        @client
      end

      private

      def gate(klass)
        case klass
        when :read
          nil
        when :write_safe
          return write_blocked if @write_mode == :ro
          nil
        when :write_dangerous, :unknown
          return write_blocked if @write_mode == :ro
          return confirm_required unless @confirmed
          nil
        end
      end

      def write_blocked
        Result.new(
          columns: [], rows: [], row_count: 0, time_ms: 0,
          applied_limit: nil, write_affected: nil,
          error_code: "WRITE_BLOCKED",
          error_message: "write blocked — :w on to enable writes on this connection"
        )
      end

      def confirm_required
        Result.new(
          columns: [], rows: [], row_count: 0, time_ms: 0,
          applied_limit: nil, write_affected: nil,
          error_code: "CONFIRM_REQUIRED",
          error_message: "confirm required — re-run with confirmed=true"
        )
      end

      def run_with_one_retry(sql)
        [run_once(sql), false]
      rescue => e
        if RETRYABLE_CODES.include?(mysql_code(e))
          @client = reconnect!
          begin
            [run_once(sql), true]
          rescue => e2
            return [Result.new(
              columns: [], rows: [], row_count: 0, time_ms: 0,
              applied_limit: nil, write_affected: nil,
              error_code: mysql_code(e2), error_message: e2.message
            ), true]
          end
        else
          [Result.new(
            columns: [], rows: [], row_count: 0, time_ms: 0,
            applied_limit: nil, write_affected: nil,
            error_code: mysql_code(e), error_message: e.message
          ), false]
        end
      end

      def run_once(sql)
        @client.query(sql, as: :array, cast_booleans: true, symbolize_keys: false)
      end

      def normalize(raw, elapsed_ms, injected, klass)
        if klass == :read
          columns = raw.respond_to?(:fields) ? raw.fields : []
          rows    = raw.respond_to?(:to_a)   ? raw.to_a   : []
          Result.new(
            columns: columns, rows: rows, row_count: rows.size,
            time_ms: elapsed_ms,
            applied_limit: injected ? @session_limit : nil,
            write_affected: nil,
            error_code: nil, error_message: nil
          )
        else
          affected = raw.respond_to?(:affected_rows) ? raw.affected_rows : nil
          Result.new(
            columns: [], rows: [], row_count: 0,
            time_ms: elapsed_ms,
            applied_limit: nil,
            write_affected: affected,
            error_code: nil, error_message: nil
          )
        end
      end

      def mysql_code(e)
        e.respond_to?(:error_number) ? e.error_number : nil
      end
    end
  end
end
