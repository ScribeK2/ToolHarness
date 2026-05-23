module ToolHarness
  class CommandDispatcher
    Command = Struct.new(:name, :args, keyword_init: true)

    KNOWN = %i[run tool target copy export pin history expiring raw help set purge q
               c d db w h limit timeout].freeze

    def self.parse(input)
      s = input.to_s.strip.sub(/\A:/, "")
      return Command.new(name: :empty, args: {}) if s.empty?

      head, *rest = s.split(/\s+/)
      name = head.to_sym
      return Command.new(name: :unknown, args: { raw: s }) unless KNOWN.include?(name)

      args = case name
             when :run    then { tool: rest[0], target: rest[1] }.compact
             when :tool   then { name: rest[0] }.compact
             when :target then { value: rest.join(" ") }
             when :copy   then { what: rest[0] || "summary" }
             when :export then { format: rest[0] || "json" }
             when :pin    then { tool: rest[0], slot: rest[1]&.to_i }.compact
             when :history then { filter: rest.join(" ") }
             when :purge  then parse_kv(rest)
             when :set    then { key: rest[0], value: rest[1..]&.join(" ") }.compact
             when :help    then { topic: rest.join(" ") }
             when :c       then parse_kv(rest)                        # :c host=... port=... user=...  or :c <profile>
             when :d       then {}
             when :db      then { name: rest[0] }.compact
             when :w       then { mode: rest[0] }.compact              # :w on / :w off
             when :h       then { index: rest[0]&.to_i }.compact
             when :limit   then { n: rest[0]&.to_i }.compact
             when :timeout then { n: rest[0]&.to_i }.compact
             else               {}
             end

      Command.new(name: name, args: args)
    end

    def self.parse_kv(parts)
      parts.each_with_object({}) do |part, h|
        k, v = part.split("=", 2)
        h[k.to_sym] = v if k && v
      end
    end
  end
end
