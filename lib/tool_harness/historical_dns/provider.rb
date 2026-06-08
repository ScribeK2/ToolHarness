require "net/http"
require "uri"
require "json"

module ToolHarness
  module HistoricalDns
    class ProviderError < StandardError
      CATEGORIES = %i[bad_key rate_limited no_credits unavailable].freeze
      attr_reader :category

      def initialize(category, message = nil)
        @category = category
        super(message || category.to_s)
      end
    end

    # Abstract provider. Subclasses implement #fetch(domain, key:) ->
    # { records: [Record], subdomains: [{name:, first_seen:, last_seen:}] }
    # and raise ProviderError on remote failure.
    class Provider
      # Per-provider HTTP timeouts (seconds). Subclasses override read_timeout when the
      # upstream is known-slow (crt.sh). Providers run concurrently, so a longer timeout
      # on one doesn't slow the overall run.
      def self.open_timeout = 3
      def self.read_timeout = 9

      def self.id            = raise(NotImplementedError, "#{name} must implement .id")
      def self.display_name  = raise(NotImplementedError, "#{name} must implement .display_name")
      def self.requires_key? = true
      def self.record_types  = []

      # Explicit list — Zeitwerk autoloads each on reference. Add providers here.
      def self.all = [Crtsh, Virustotal, Whoisfreaks]

      def available?(store)
        return true unless self.class.requires_key?
        store.secret_for(self.class.id).present?
      end

      def fetch(_domain, key: nil)
        raise NotImplementedError, "#{self.class.name} must implement #fetch"
      end

      private

      # HTTP seam — stubbed in tests. -> { status: Integer, body: parsed|nil, error: String|nil }
      def http_get_json(url, headers = {})
        uri  = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.open_timeout = self.class.open_timeout
        http.read_timeout = self.class.read_timeout
        resp = http.get(uri.request_uri, { "Accept" => "application/json" }.merge(headers))
        body = (JSON.parse(resp.body) rescue nil)
        { status: resp.code.to_i, body: body, error: nil }
      rescue StandardError => e
        { status: 0, body: nil, error: e.message }
      end

      def raise_for_status(status, error)
        case status
        when 401, 403 then raise ProviderError.new(:bad_key, "#{self.class.display_name} rejected the API key (HTTP #{status})")
        when 429      then raise ProviderError.new(:rate_limited, "#{self.class.display_name} rate limit reached (HTTP 429)")
        when 0        then raise ProviderError.new(:unavailable, "#{self.class.display_name} request failed: #{error || 'network error'}")
        else               raise ProviderError.new(:unavailable, "#{self.class.display_name} returned HTTP #{status}")
        end
      end
    end
  end
end
