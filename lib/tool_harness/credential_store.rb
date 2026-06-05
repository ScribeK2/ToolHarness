require "yaml"
require "fileutils"
require_relative "sql/secret_box"

module ToolHarness
  # Encrypted-at-rest store for tool credentials: provider API keys (kind "api_key")
  # and per-host credentials (kind "host"). Mirrors Sql::ConnectionStore mechanics.
  # Secrets are only ever returned by #secret_for (decrypted at point-of-use).
  class CredentialStore
    CREDENTIALS_SALT = "toolharness.credentials.secret".freeze
    KINDS = %w[api_key host].freeze
    attr_reader :last_load_error

    def initialize(path: self.class.default_path)
      @path = path
      @last_load_error = nil
      load!
    end

    def self.default_path
      config_dir = ENV["TOOLHARNESS_CONFIG_DIR"] ||
                   File.join(ENV["XDG_CONFIG_HOME"] || File.join(Dir.home, ".config"), "toolharness")
      File.join(config_dir, "credentials.yml")
    end

    # Metadata for every entry, secret stripped. (locked flag present if undecryptable.)
    def entries
      load!
      @entries.map { |e| e.except(:secret_enc) }
    end

    def entry(id)
      @entries.find { |e| e[:id] == id.to_s }&.except(:secret_enc)
    end

    def for_kind(kind)
      entries.select { |e| e[:kind] == kind.to_s }
    end

    # The ONLY method that returns a plaintext secret. nil if missing/locked/undecryptable.
    def secret_for(id)
      e = @entries.find { |x| x[:id] == id.to_s }
      return nil if e.nil? || e[:locked]
      ToolHarness::Sql::SecretBox.decrypt(e[:secret_enc], salt: CREDENTIALS_SALT)
    rescue ToolHarness::Sql::SecretBox::DecryptError
      nil
    end

    def save(id:, kind:, secret:, label: nil, host: nil, user: nil)
      @entries.reject! { |e| e[:id] == id.to_s }
      @entries << {
        id:           id.to_s,
        kind:         kind.to_s,
        label:        (label.presence || id).to_s,
        host:         host.presence,
        user:         user.presence,
        secret_enc:   ToolHarness::Sql::SecretBox.encrypt(secret.to_s, salt: CREDENTIALS_SALT),
        created_at:   Time.current.iso8601,
        last_used_at: nil
      }
      persist!
    end

    def delete(id)
      @entries.reject! { |e| e[:id] == id.to_s }
      persist!
    end

    def touch!(id)
      e = @entries.find { |x| x[:id] == id.to_s }
      return unless e
      e[:last_used_at] = Time.current.iso8601
      persist!
    end

    private

    def load!
      @entries = []
      return unless File.exist?(@path)
      raw = YAML.safe_load(File.read(@path), permitted_classes: [Time, Symbol], aliases: false)
      return unless raw.is_a?(Array)
      @entries = raw.map { |h| symbolize(h) }.map { |e| flag_locked(e) }
    rescue Psych::SyntaxError, ArgumentError, TypeError => e
      @last_load_error = RuntimeError.new("YAML #{e.class}: #{e.message}")
      @entries = []
    end

    def flag_locked(e)
      ToolHarness::Sql::SecretBox.decrypt(e[:secret_enc], salt: CREDENTIALS_SALT)
      e
    rescue ToolHarness::Sql::SecretBox::DecryptError
      e.merge(locked: true)
    end

    def symbolize(h)
      h.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(@path))
      to_dump = @entries.map { |e| e.except(:locked).transform_keys(&:to_s) }
      File.open(@path, "w", 0o600) { |f| f.write(YAML.dump(to_dump)) }
    end
  end
end
