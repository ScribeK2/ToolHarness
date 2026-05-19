require "yaml"
require "fileutils"
require_relative "secret_box"

module ToolHarness
  module Sql
    class ConnectionStore
      DEFAULT_PORT = 4000
      attr_reader :last_load_error

      def initialize(path: self.class.default_path)
        @path = path
        @last_load_error = nil
        load!
      end

      def self.default_path
        config_dir = ENV["TOOLHARNESS_CONFIG_DIR"] ||
                     File.join(ENV["XDG_CONFIG_HOME"] || File.join(Dir.home, ".config"), "toolharness")
        File.join(config_dir, "connections.yml")
      end

      # [{ name:, host:, port:, user:, default_database:, default_mode:, tls_mode:,
      #    created_at:, last_used_at:, locked: }]  (password NEVER returned here)
      def profiles
        load!
        @profiles.map { |p| p.except(:password_enc) }
      end

      def find(name)
        @profiles.find { |p| p[:name] == name.to_s }
      end

      def password_for(name)
        p = @profiles.find { |x| x[:name] == name.to_s }
        return nil if p.nil? || p[:locked]
        SecretBox.decrypt(p[:password_enc])
      rescue SecretBox::DecryptError
        nil
      end

      def save(name:, host:, port:, user:, password:, default_database:, default_mode:, tls_mode:)
        @profiles.reject! { |p| p[:name] == name.to_s }
        @profiles << {
          name:             name.to_s,
          host:             host.to_s,
          port:             port.to_i,
          user:             user.to_s,
          password_enc:     SecretBox.encrypt(password.to_s),
          default_database: default_database.to_s,
          default_mode:     default_mode.to_s,
          tls_mode:         tls_mode.to_s,
          created_at:       Time.current.iso8601,
          last_used_at:     nil
        }
        persist!
      end

      def touch!(name)
        return unless (p = find(name))
        p[:last_used_at] = Time.current.iso8601
        persist!
      end

      def delete(name)
        @profiles.reject! { |p| p[:name] == name.to_s }
        persist!
      end

      # Allow tests to swap in a fake client class.
      def self.client_factory
        @client_factory ||= ->(opts) { Mysql2::Client.new(opts) }
      end

      def self.client_factory=(callable)
        @client_factory = callable
      end

      IDLE_REAP_AFTER = 15 * 60 # seconds

      # Class-level pool so all ConnectionStore instances share the same open clients.
      def self.pool
        @pool ||= {}
      end

      def self.pool=(h)
        @pool = h
      end

      def client_for(name)
        cache = self.class.pool
        entry = cache[name]
        if entry.nil? || idle?(entry)
          close_entry(entry) if entry
          entry = open_client(name)
          cache[name] = entry
        end
        entry[:last_used] = Time.current.to_f
        entry[:client]
      end

      def disconnect(name)
        cache = self.class.pool
        return unless cache[name]
        close_entry(cache.delete(name))
      end

      def disconnect_all
        self.class.pool.each_value { |e| close_entry(e) }
        self.class.pool = {}
      end

      def reset_pool!
        disconnect_all
      end

      def reconnect(name)
        disconnect(name)
        client_for(name)
      end

      private

      def open_client(name)
        profile = find(name) or raise ArgumentError, "no such profile: #{name}"
        password = password_for(name) or raise ArgumentError, "password for #{name} could not be decrypted"
        opts = {
          host:            profile[:host],
          port:            profile[:port],
          username:        profile[:user],
          password:        password,
          database:        (profile[:default_database] unless profile[:default_database].to_s.empty?),
          connect_timeout: 5,
          read_timeout:    30,
          ssl_mode:        tls_to_ssl_mode(profile[:tls_mode])
        }.compact
        client = self.class.client_factory.call(opts)
        touch!(name)
        { client: client, last_used: Time.current.to_f }
      end

      def idle?(entry)
        (Time.current.to_f - entry[:last_used]) > IDLE_REAP_AFTER
      end

      def close_entry(entry)
        entry[:client].close rescue nil
      end

      def tls_to_ssl_mode(value)
        case value.to_s
        when "required" then :required
        when "disabled" then :disabled
        else                 :preferred
        end
      end

      def load!
        @profiles = []
        return unless File.exist?(@path)
        raw = YAML.safe_load(File.read(@path), permitted_classes: [Time, Symbol], aliases: false)
        return unless raw.is_a?(Array)
        @profiles = raw.map { |h| symbolize(h) }.map { |p| flag_locked(p) }
      rescue Psych::SyntaxError, ArgumentError, TypeError => e
        @last_load_error = RuntimeError.new("YAML #{e.class}: #{e.message}")
        @profiles = []
      end

      def flag_locked(p)
        SecretBox.decrypt(p[:password_enc])
        p
      rescue SecretBox::DecryptError
        p.merge(locked: true)
      end

      def symbolize(h)
        h.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
      end

      def persist!
        FileUtils.mkdir_p(File.dirname(@path))
        to_dump = @profiles.map { |p| p.except(:locked).transform_keys(&:to_s) }
        File.open(@path, "w", 0o600) { |f| f.write(YAML.dump(to_dump)) }
      end
    end
  end
end
