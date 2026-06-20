# frozen_string_literal: true

# Builds the full env hash to write to a Dokku app during a sync.
#
# We always include every EnvironmentVariable row (including the ones
# flagged is_dokku_internal — those are the Dokku-injected link URLs
# like DATABASE_URL / REDIS_URL that were originally set by
# `postgres:link` and friends).
#
# Safety net: any key currently set on the host that isn't in our DB
# hash is preserved across the clear. This covers every category of
# Dokku-injected value we don't actively manage:
#
#   - Linked-service URLs (DATABASE_URL / REDIS_URL / MONGO_URL /
#     MYSQL_URL and their _PRIVATE_URL variants). Dokku only sets these
#     at link-time (`postgres:link`); it does not re-inject them on
#     restart or deploy, so config:clear would silently strip them.
#
#   - Shared vars (Dokku >= 0.34's `config:set --shared`). Stored at
#     the host level and inherited by every app. config:clear at the
#     app level does not touch them, but if any copy ends up in the
#     per-app ENV file we want to keep it.
#
#   - Plugin-injected keys (DOKKU_*, etc.) that some Dokku plugins
#     write into the per-app env.
#
# Global vars (`config:set --global`) are intentionally NOT preserved
# here — they live in `/var/lib/dokku/config/--global/ENV` and are
# merged into containers at start time by Dokku itself, never by
# config:clear at the app level. Including them would duplicate them
# into the per-app file and break the "global is global" contract.
module DokkuEnvBatchable
  extend ActiveSupport::Concern

  LINK_URL_KEYS = %w[
    DATABASE_URL REDIS_URL MONGO_URL MYSQL_URL
    DATABASE_PRIVATE_URL REDIS_PRIVATE_URL
  ].freeze

  private

  def build_full_env_hash(service, engine)
    env_hash = service.environment_variables.pluck(:key, :value).to_h
    preserve_host_only_keys(service, engine, env_hash)
    env_hash
  end

  # For every key present on the host's per-app ENV that is NOT in
  # the DB hash and NOT a placeholder (${{ shared.X }}), carry it
  # forward into the new write. This is the only way config:clear
  # becomes safe for env vars we don't directly manage.
  def preserve_host_only_keys(service, engine, env_hash)
    show = engine.config_show(service.dokku_app_name)
    return unless show[:success]

    show[:output].each_line do |line|
      line = line.strip
      next unless line.include?("=")

      key, _, value = line.partition("=")
      key = key.strip
      value = value.strip
      next if value.blank? || value.start_with?("$")
      next if env_hash.key?(key)

      env_hash[key] = value
    end
  end
end
