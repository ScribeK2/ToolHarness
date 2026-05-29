module Investigations
  class Track
    attr_reader :key, :label, :probes, :correlator

    def initialize(key:, label:, probes:, correlator:)
      @key = key
      @label = label
      @probes = probes
      @correlator = correlator
    end

    def self.definitions
      @definitions ||= {
        "orientation" => new(
          key: "orientation",
          label: "Orientation",
          probes: %w[whois_lookup dns_lookup hosting_diagnostic],
          correlator: Investigations::OrientationCorrelator
        )
      }
    end

    def self.find(key) = definitions.fetch(key.to_s)
    def self.all       = definitions.values
  end
end
