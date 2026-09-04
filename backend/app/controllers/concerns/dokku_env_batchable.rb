# frozen_string_literal: true

# Builds the full env hash to write to a Dokku app during a sync.
#
# This concern is the canonical entry point for any code path that
# writes a service's env to the host. It understands the full set of
# env-var sources RailDock manages, plus the Dokku-level sources we
# don't directly control:
#
#   - User env:        EnvironmentVariable rows set via the UI or API.
#   - Shared vars:     Project.shared_vars referenced as ${{ shared.X }}
#                      in env values. Resolved here using
#                      ManifestParser.resolve_runtime so the literal
#                      ${{ shared.X }} never reaches the host.
#   - Linked vars:     ${{ linked.SERVICE.VAR }} references, resolved
#                      against the linked service's EnvironmentVariable
#                      rows.
#   - Dokku link URLs: EnvironmentVariable rows flagged
#                      is_dokku_internal=true (DATABASE_URL, REDIS_URL,
#                      etc. — set at link-time by `postgres:link`).
#   - Host-only keys:  Anything currently set on the host that isn't
#                      in our DB hash (DOKKU_* plugin vars, etc.). We
#                      preserve these across the clear so we never
#                      silently strip something we don't manage.
#
# Global vars (`config:set --global`) are intentionally NOT touched —
# they live in `/var/lib/dokku/config/--global/ENV` and Dokku injects
# them at container start, never via the per-app file. Including them
# here would duplicate them and break the "global is global" contract.
module DokkuEnvBatchable
  extend ActiveSupport::Concern

  private

  # When a service declares a start_command in its manifest, forward it to
  # Dokku via DOKKU_DOCKERFILE_CMD so the container runs it instead of the
  # image's default CMD. Many docker images (e.g. bitcart-admin ending in
  # CMD ["sh"]) exit immediately when started non-interactively, which makes
  # Dokku report "Container state: exited" on every deploy.
  def build_full_env_hash(service, engine)
    env_hash = service.environment_variables.pluck(:key, :value).to_h
    resolve_manifest_placeholders(service, env_hash)
    preserve_host_only_keys(service, engine, env_hash)
    apply_start_command(service, env_hash)
    env_hash
  end

  def apply_start_command(service, env_hash)
    start_command = service.start_command
    return env_hash if start_command.blank?

    env_hash["DOKKU_DOCKERFILE_CMD"] = start_command
    env_hash
  end

  # Walk every value in env_hash and substitute ${{ shared.X }} /
  # ${{ linked.SERVICE.VAR }} markers. This mirrors what the manifest
  # reconciler does at deploy time, but here we do it inline so the
  # batched config:set call never writes a literal placeholder.
  #
  # If a marker can't be resolved (shared var missing, linked service
  # unreachable), the key is REMOVED from env_hash so config_replace_all
  # never writes a literal "[SHARED:/[LINKED:..." marker to Dokku —
  # writing one would silently overwrite the correctly-resolved value
  # that resolve_runtime_values already set during manifest apply.
  #
  # The source expression remains in the database. Resolution is a deploy-time
  # concern so changes to shared or linked values propagate on the next sync.
  def resolve_manifest_placeholders(service, env_hash)
    project = service.project
    return unless project

    linked_services = service.linked_services.to_a

    service.environment_variables.each do |ev|
      original = ev.value.to_s

      # Only attempt resolution if the value contains a marker or reference
      next unless original.match?(ManifestParser::ENV_VALUE_REFERENCE_PATTERN)

      resolved = ManifestParser.resolve_runtime(original, project, service, linked_services)

      if resolved.match?(ManifestParser::ENV_VALUE_REFERENCE_PATTERN)
        # Resolution failed — the value still contains a marker.
        # Remove it from env_hash so config_replace_all doesn't write
        # literal marker strings to Dokku.
        Rails.logger.warn "Unresolved marker in #{service.dokku_app_name}##{ev.key}: #{original} → #{resolved} — excluded from deploy"
        env_hash.delete(ev.key)
      else
        env_hash[ev.key] = resolved
      end
    end
  end

  # For every key present on the host's per-app ENV that is NOT in
  # the DB hash, carry it forward into the new write. Preserves any
  # Dokku plugin-injected key (DOKKU_*, etc.) we don't track.
  def preserve_host_only_keys(service, engine, env_hash)
    exported = engine.config_export_json(service.dokku_app_name)
    return unless exported[:success]

    JSON.parse(exported[:output]).each do |key, value|
      next if env_hash.key?(key)

      env_hash[key] = value
    end
  rescue JSON::ParserError => e
    Rails.logger.warn "Unable to preserve host config for #{service.dokku_app_name}: #{e.message}"
  end
end
