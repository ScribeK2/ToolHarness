require "yaml"
require "fileutils"
require "tempfile"

module ToolHarness
  module Sql
    class RecipeStore
      STARTERS = [
        { name: "SHOW TABLES",                 sql: "SHOW TABLES;" },
        { name: "SHOW DATABASES",              sql: "SHOW DATABASES;" },
        { name: "SHOW CREATE TABLE <table>",   sql: "SHOW CREATE TABLE <table>;" },
        { name: "SELECT VERSION()",            sql: "SELECT VERSION();" },
        { name: "SHOW PROCESSLIST",            sql: "SHOW PROCESSLIST;" },
        { name: "SHOW VARIABLES LIKE '%'",     sql: "SHOW VARIABLES LIKE '%';" }
      ].freeze

      attr_reader :last_load_error

      def initialize(path: self.class.default_path)
        @path = path
        @last_load_error = nil
        load!
      end

      def self.default_path
        config_dir = ENV["TOOLHARNESS_CONFIG_DIR"] ||
                     File.join(ENV["XDG_CONFIG_HOME"] || File.join(Dir.home, ".config"), "toolharness")
        File.join(config_dir, "recipes.yml")
      end

      # Returns starters + saved recipes, with saved shadowing starters by name.
      # Each entry: { name:, sql:, created_at:, source: :starter | :saved }
      def all
        load!
        starter_names = STARTERS.map { |s| s[:name] }
        saved_names   = @saved.map  { |s| s[:name] }
        starters_visible = STARTERS.reject { |s| saved_names.include?(s[:name]) }
                                   .map    { |s| s.merge(source: :starter) }
        saved_decorated  = @saved.map      { |s| s.merge(source: :saved) }
        starters_visible + saved_decorated
      end

      def save(name:, sql:)
        load!
        @saved.reject! { |r| r[:name] == name.to_s }
        @saved << {
          name:       name.to_s,
          sql:        sql.to_s,
          created_at: Time.current.iso8601
        }
        persist!
        true
      end

      def delete(name:)
        load!
        before = @saved.size
        @saved.reject! { |r| r[:name] == name.to_s }
        if @saved.size < before
          persist!
          true
        else
          false
        end
      end

      def exists?(name:)
        load!
        @saved.any? { |r| r[:name] == name.to_s }
      end

      private

      def load!
        @saved = []
        @last_load_error = nil
        return unless File.exist?(@path)
        raw = YAML.safe_load(File.read(@path), permitted_classes: [Time, Symbol], aliases: false)
        return unless raw.is_a?(Array)
        @saved = raw.map { |h| symbolize(h) }
      rescue Psych::SyntaxError, ArgumentError, TypeError => e
        @last_load_error = RuntimeError.new("YAML #{e.class}: #{e.message}")
        @saved = []
      end

      def symbolize(h)
        h.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
      end

      def persist!
        FileUtils.mkdir_p(File.dirname(@path))
        to_dump = @saved.map { |r| r.transform_keys(&:to_s) }
        tmp = Tempfile.new(["recipes", ".yml"], File.dirname(@path))
        begin
          tmp.write(YAML.dump(to_dump))
          tmp.close
          File.chmod(0o600, tmp.path)
          File.rename(tmp.path, @path)
        ensure
          tmp.unlink if File.exist?(tmp.path)
        end
      end
    end
  end
end
