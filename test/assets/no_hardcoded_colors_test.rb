require "test_helper"

# Light themes only work because every view renders colors through semantic
# tokens (bg/fg/blue/...). This guard keeps it that way: no literal Tailwind
# palette utilities (text-white, bg-slate-700, ...) and no hex literals in
# view/JS source. theme CSS files and the boot/picker swatches are exempt.
class NoHardcodedColorsTest < ActiveSupport::TestCase
  ROOTS = [Rails.root.join("app", "views"), Rails.root.join("app", "javascript")].freeze

  LITERAL_UTILITY = /\b(?:text|bg|border|fill|stroke|ring|from|via|to)-(?:white|black|slate|zinc|gray|neutral|stone)(?:-\d{2,3})?\b/
  HEX             = /#[0-9a-fA-F]{6}\b/

  test "no literal palette utilities in views or JS" do
    offenders = source_files.flat_map do |f|
      File.readlines(f).each_with_index.filter_map do |line, i|
        "#{f}:#{i + 1}: #{line.strip}" if line.match?(LITERAL_UTILITY)
      end
    end
    assert_empty offenders, "Use semantic tokens (bg/fg/blue/...) not literal colors:\n#{offenders.join("\n")}"
  end

  test "no hex color literals in views or JS (swatches use var() tokens)" do
    offenders = source_files.flat_map do |f|
      File.readlines(f).each_with_index.filter_map do |line, i|
        "#{f}:#{i + 1}: #{line.strip}" if line.match?(HEX)
      end
    end
    assert_empty offenders, "Use semantic tokens / var() not hex literals:\n#{offenders.join("\n")}"
  end

  private

  def source_files
    ROOTS.flat_map { |r| Dir.glob(r.join("**", "*.{erb,js}")) }
  end
end
