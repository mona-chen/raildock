# frozen_string_literal: true

# Seed the built-in server-capability plugins on boot. This is idempotent and
# safe to run on every startup.
Rails.application.config.after_initialize do
  begin
    PluginRegistry.seed! if defined?(PluginRegistry) && ActiveRecord::Base.connection.table_exists?("plugins")
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => e
    Rails.logger.warn "PluginRegistry seed skipped: #{e.message}"
  end
end
