module ToolHarness
  module Sql
    Result = Struct.new(
      :columns, :rows, :row_count, :time_ms,
      :applied_limit, :write_affected, :error_code, :error_message,
      keyword_init: true
    ) do
      def success?
        error_message.nil?
      end
    end
  end
end
