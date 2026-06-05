require "active_support/message_encryptor"

module ToolHarness
  module Sql
    class SecretBox
      class DecryptError < StandardError; end

      SALT = "toolharness.sql.connection_password".freeze
      KEY_LEN = ActiveSupport::MessageEncryptor.key_len

      def self.encrypt(plaintext, key: default_key, salt: SALT)
        encryptor(key, salt).encrypt_and_sign(plaintext)
      end

      def self.decrypt(ciphertext, key: default_key, salt: SALT)
        encryptor(key, salt).decrypt_and_verify(ciphertext)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage,
             ActiveSupport::MessageVerifier::InvalidSignature => e
        raise DecryptError, "could not decrypt: #{e.class}"
      end

      def self.encryptor(key, salt = SALT)
        derived = ActiveSupport::KeyGenerator.new(key.to_s, hash_digest_class: OpenSSL::Digest::SHA256)
                    .generate_key(salt, KEY_LEN)
        ActiveSupport::MessageEncryptor.new(derived)
      end

      def self.default_key
        Rails.application.secret_key_base
      end
    end
  end
end
