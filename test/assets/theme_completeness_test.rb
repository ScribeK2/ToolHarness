require "test_helper"

# The load-bearing guard: every theme in config/themes.yml must have a
# dedicated CSS file under app/assets/tailwind/themes/<key>.css with a
# complete [data-theme] block, AND application.css must @import that file.
# An incomplete theme fails CI.
class ThemeCompletenessTest < ActiveSupport::TestCase
  TOKENS = %w[
    color-bg color-surface color-elevated color-sunken color-line
    color-fg color-fg-dim color-mute
    color-blue color-cyan color-green color-purple color-orange color-red color-yellow
    color-accent color-accent-2
  ].freeze

  THEMES_DIR = Rails.root.join("app", "assets", "tailwind", "themes")
  ENTRY      = Rails.root.join("app", "assets", "tailwind", "application.css")

  test "every registered theme has a complete per-file CSS block and is imported in application.css" do
    entry_css = File.read(ENTRY)

    ToolHarness::Themes.all.each do |theme|
      key = theme[:key]
      theme_file = THEMES_DIR.join("#{key}.css")

      assert theme_file.exist?, "Missing theme file: app/assets/tailwind/themes/#{key}.css"

      theme_css = File.read(theme_file)

      assert_match(/\[data-theme=["']#{Regexp.escape(key)}["']\]\s*\{/, theme_css,
                   "#{key}.css has no [data-theme=\"#{key}\"] block")

      block_match = theme_css.match(/\[data-theme=["']#{Regexp.escape(key)}["']\]\s*\{([^}]+)\}/)
      assert block_match, "Could not extract [data-theme=\"#{key}\"] block from #{key}.css"
      block_css = block_match[1]

      assert_match(/color-scheme\s*:/, block_css, "#{key}.css block missing color-scheme")

      block_css =~ /color-scheme\s*:\s*(\w+)/
      assert_equal theme[:scheme], $1,
                   "#{key}.css color-scheme (#{$1.inspect}) must match registry scheme (#{theme[:scheme].inspect})"

      TOKENS.each do |token|
        assert_match(/--#{token}\s*:/, block_css, "#{key}.css block missing --#{token}")
      end

      assert_match(%r{@import\s+["']\./themes/#{Regexp.escape(key)}\.css["']}, entry_css,
                   "application.css does not @import themes/#{key}.css")
    end
  end
end
