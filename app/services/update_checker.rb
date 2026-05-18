require "net/http"
require "json"

class UpdateChecker
  CACHE_KEY     = "update_check:latest".freeze
  CACHE_TTL     = 24.hours
  GITHUB_API    = "https://api.github.com/repos/ScribeK2/ToolHarness/releases/latest".freeze
  HTTP_TIMEOUT  = 5

  class << self
    def current_version
      @current_version ||= File.read(Rails.root.join("VERSION")).strip
    end

    def banner_data
      cached = Rails.cache.read(CACHE_KEY)
      return nil unless cached

      latest = cached["tag_name"].to_s.sub(/\Av/, "")
      return nil if latest.empty? || !newer?(latest, current_version)

      { available: true, version: latest, url: cached["html_url"] }
    end

    def refresh!
      uri = URI(GITHUB_API)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "ToolHarness/#{current_version}"
        req["Accept"]     = "application/vnd.github+json"
        resp = http.request(req)
        return unless resp.is_a?(Net::HTTPSuccess)

        body = JSON.parse(resp.body)
        Rails.cache.write(CACHE_KEY, body.slice("tag_name", "html_url"), expires_in: CACHE_TTL)
      end
    rescue StandardError => e
      Rails.logger.info("UpdateChecker.refresh! skipped: #{e.class}: #{e.message}")
      nil
    end

    private

    def newer?(latest, current)
      Gem::Version.new(latest) > Gem::Version.new(current)
    rescue ArgumentError
      false
    end
  end
end
