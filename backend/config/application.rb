require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Add cookies/session middleware required by ActionCable
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_raildock_session"

    # Fallback secret_key_base from environment when credentials.yml.enc is missing.
    # Production must be configured explicitly; random boot keys invalidate sessions
    # and make signed values unreliable across restarts.
    config.secret_key_base = ENV["RAILS_MASTER_KEY"].presence || SecureRandom.hex(64)

    # Keep Active Record encryption off Rails credentials so fresh installs can boot
    # from environment variables alone. This avoids a credentials-file decryption
    # failure when the generated master key does not match the repository seed.
    config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || ENV["RAILS_MASTER_KEY"].presence || SecureRandom.hex(32)
    config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || ENV["RAILS_MASTER_KEY"].presence || SecureRandom.hex(32)
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || ENV["RAILS_MASTER_KEY"].presence || SecureRandom.hex(32)

    # Public app URL used to build invitation links. Falls back to localhost.
    config.x.app_url = ENV["APP_URL"].presence
    config.action_mailer.default_url_options = {
      host: ENV.fetch("APP_HOST", "localhost"),
      port: ENV["APP_PORT"].presence&.to_i,
      protocol: ENV.fetch("APP_PROTOCOL", "http")
    }.compact
    config.action_mailer.raise_delivery_errors = ENV.fetch("MAIL_RAISE_DELIVERY_ERRORS", "false") == "true"

    # Prefer database SMTP settings over env vars after boot.
    config.after_initialize do
      if ActiveRecord::Base.connection.data_source_exists?("system_settings")
        SmtpService.apply_from_db!
      elsif ENV["SMTP_ADDRESS"].present?
        SmtpService.apply_env_settings!
      end
    end
  end
end
