module Investigations
  class Track
    # A single probe in a track's battery. depends_on/target are nil for the common
    # case (input = the investigation's domain, enqueued immediately). When set, the
    # StepScheduler resolves the input from the named probe's result before enqueuing.
    # `target` is a Symbol naming a resolver strategy (e.g. :primary_mx_host).
    ProbeSpec = Struct.new(:tool_key, :depends_on, :target, keyword_init: true)

    attr_reader :key, :label, :correlator, :specs

    def initialize(key:, label:, probes:, correlator:)
      @key        = key
      @label      = label
      @correlator = correlator
      @specs      = probes.map { |p| normalize(p) }
    end

    # Tool keys in battery order (back-compat: callers/tests expect a string array).
    def probes = @specs.map(&:tool_key)

    def self.definitions
      @definitions ||= {
        "orientation" => new(
          key: "orientation",
          label: "Orientation",
          probes: %w[whois_lookup dns_lookup hosting_diagnostic],
          correlator: Investigations::OrientationCorrelator
        ),
        "email_delivery" => new(
          key: "email_delivery",
          label: "Email Delivery",
          probes: [
            "dns_lookup", "email_auth_check",
            { tool: "hosting_diagnostic", depends_on: "dns_lookup", target: :primary_mx_host },
            { tool: "blacklist", depends_on: "dns_lookup", target: :primary_mx_host }
          ],
          correlator: Investigations::EmailDeliveryCorrelator
        ),
        "hosting_website" => new(
          key: "hosting_website",
          label: "Hosting & Website",
          probes: %w[dns_lookup hosting_diagnostic website_inspect ssl_inspect],
          correlator: Investigations::HostingWebsiteCorrelator
        )
      }
    end

    def self.find(key)    = definitions.fetch(key.to_s)
    def self.exists?(key) = definitions.key?(key.to_s)
    def self.all          = definitions.values

    private

    def normalize(probe)
      return ProbeSpec.new(tool_key: probe, depends_on: nil, target: nil) if probe.is_a?(String)

      ProbeSpec.new(tool_key: probe.fetch(:tool), depends_on: probe[:depends_on], target: probe[:target])
    end
  end
end
