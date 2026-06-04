require "yaml"

module ToolHarness
  # Reads config/themes.yml — the picker's metadata registry. Palette colors
  # live in app/assets/tailwind/themes/<key>.css, not here, so there is no
  # color duplication. The first entry is the default theme.
  module Themes
    PATH = Rails.root.join("config", "themes.yml")

    class << self
      # [{ key:, label:, scheme: }, ...] in file order. Keys are strings.
      def all
        @all ||= begin
          raw = YAML.safe_load(File.read(PATH)) || []
          raw.map { |h| { key: h["key"].to_s, label: h["label"].to_s, scheme: h["scheme"].to_s } }
        end
      end

      def keys
        all.map { |t| t[:key] }
      end

      def default_key
        all.first&.fetch(:key) || raise("config/themes.yml is empty or missing")
      end

      # { "nord" => "dark", "catppuccin-latte" => "light", ... }
      def scheme_map
        all.each_with_object({}) { |t, acc| acc[t[:key]] = t[:scheme] }
      end

      # Test seam: drop the memoized cache.
      def reload!
        @all = nil
      end
    end
  end
end
