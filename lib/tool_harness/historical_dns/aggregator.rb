require "date"

module ToolHarness
  module HistoricalDns
    # Pure: merges normalized records into a per-type timeline + approximate change list.
    class Aggregator
      def self.call(records) = new(records).call

      def initialize(records)
        @records = Array(records)
      end

      def call
        timeline = group_and_mark(merge(@records))
        { timeline: timeline, changes: derive_changes(timeline) }
      end

      private

      # [type, value] -> one merged hash (min first_seen, max last_seen, union sources).
      def merge(records)
        groups = {}
        records.each do |r|
          g = (groups[[r.type, r.value]] ||= { type: r.type, value: r.value, first_seen: r.first_seen, last_seen: r.last_seen, sources: [] })
          g[:first_seen] = [g[:first_seen], r.first_seen].compact.min
          g[:last_seen]  = [g[:last_seen],  r.last_seen].compact.max
          g[:sources]   |= Array(r.sources)
        end
        groups.values
      end

      def group_and_mark(merged)
        merged.group_by { |m| m[:type] }.transform_values do |recs|
          max_last = recs.map { |m| m[:last_seen] }.compact.max
          recs.map { |m| m.merge(current: m[:last_seen].nil? || m[:last_seen] == max_last) }
              .sort_by { |m| [m[:first_seen] || Date.new(0), m[:value]] }
        end
      end

      # Group a type's records into eras by first_seen month; emit a transition per era boundary.
      def derive_changes(timeline)
        timeline.flat_map do |type, recs|
          eras = recs.select { |m| m[:first_seen] }
                     .group_by { |m| m[:first_seen].strftime("%Y-%m") }
                     .sort_by { |month, _| month }
          next [] if eras.size < 2
          eras.each_cons(2).map do |(_, prev), (month, curr)|
            { type: type, from: prev.map { |m| m[:value] }, to: curr.map { |m| m[:value] }, approx_date: month }
          end
        end
      end
    end
  end
end
