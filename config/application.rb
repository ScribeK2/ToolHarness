require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ToolHarness
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # AppImage runtime: when launched via AppRun, writes are redirected
    # off the read-only squashfs to XDG-anchored locations. In dev these
    # env vars are unset and Rails uses the in-tree defaults.
    if (state_dir = ENV["TOOLHARNESS_STATE_DIR"])
      config.paths["log"] = File.join(state_dir, "log", "#{Rails.env}.log")
      config.paths["tmp"] = File.join(state_dir, "tmp")
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
