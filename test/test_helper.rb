ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"  # Object#stub for class-method stubbing in tests

# Ensure routes (and therefore Devise.mappings) are populated before any test
# runs. Without this, Devise's sign_in helper raises "Could not find a valid
# mapping" when a test signs in a freshly-created user before any HTTP request
# has triggered lazy route loading.
Rails.application.reload_routes!

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Wire up Devise's sign_in / sign_out helpers for integration tests.
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
