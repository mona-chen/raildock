# frozen_string_literal: true

# Builds the full env hash to write to a Dokku app during a sync.
#
# We always include every EnvironmentVariable row (including the ones
# flagged is_dokku_internal — those are the Dokku-injected link URLs
# like DATABASE_URL / REDIS_URL that were originally set by
# `postgres:link` and friends).
#
# Safety net: if a known link URL is missing from the DB (e.g. the
# service was created before ServiceLinkSetup ran, or the row was
# deleted), we read the live host env before clearing and preserve any
# values we find. This prevents config:clear from wiping a link the
# user has not opted into managing from RailDock.
module DokkuEnvBatchable
  extend ActiveSupport::Concern

  LINK_URL_KEYS = %w[
    DATABASE_URL REDIS_URL MONGO_URL MYSQL_URL
    DATABASE_PRIVATE_URL REDIS_PRIVATE_URL
  ].freeze

  private

  def build_full_env_hash(service, engine)
    env_hash = service.environment_variables.pluck(:key, :value).to_h
    preserve_missing_link_urls(service, engine, env_hash)
    env_hash
  end

  def preserve_missing_link_urls(service, engine, env_hash)
    missing = LINK_URL_KEYS - env_hash.keys
    return if missing.empty?

    show = engine.config_show(service.dokku_app_name)
    return unless show[:success]

    show[:output].each_line do |line|
      line = line.strip
      next unless line.include?("=")

      key, _, value = line.partition("=")
      key = key.strip
      value = value.strip
      next if value.blank? || value.start_with?("$")

      env_hash[key] = value if missing.include?(key)
    end
  end
end
