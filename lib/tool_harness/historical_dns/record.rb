require "date"

module ToolHarness
  module HistoricalDns
    # A single observed DNS record, normalized so the same record from two
    # providers collapses to one. first_seen/last_seen are Date|nil.
    Record = Struct.new(:type, :value, :first_seen, :last_seen, :sources, keyword_init: true) do
      RECORD_TYPES = %i[a aaaa ns mx txt soa cname spf].freeze

      def key = [type, value]
    end
  end
end
