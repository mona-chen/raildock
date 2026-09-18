# frozen_string_literal: true

# Translates a service's static-site settings into the build env and process
# command the selected Dokku builder actually understands.
#
# A static site is a frontend that builds to a directory of files and is served
# by a plain web server, not by the app's own `start` script. Dokku has no
# first-class concept for this, so RailDock borrows each builder's native SPA
# support and then supplies the process command Dokku's scheduler needs.
#
# Why the process command has to be supplied at all:
#
#   * Dokku's railpack builder stage runs `ENTRYPOINT []` on top of the
#     railpack image. Per the Dockerfile spec, setting ENTRYPOINT resets the
#     inherited CMD, so the image's `caddy run ...` command disappears and the
#     container starts with no command ("no command specified").
#   * The nixpacks builder stage sets its own ENTRYPOINT wrapper, which clears
#     the CMD the same way.
#
# The docker-local scheduler reads `dockerfile-start-cmd` for every
# non-herokuish image, so writing the serving command there makes both builders
# start the static server. See docs/plans/2026-09-18-001-fix-static-site-deploys-plan.md.
class StaticSiteConfigurator
  # Builders that can produce and serve a static build.
  STATIC_BUILDERS = %w[railpack nixpacks].freeze

  # Builders whose build/serve behavior RailDock must not touch. A Dockerfile
  # deploy owns its own serving strategy.
  PASSTHROUGH_BUILDERS = %w[dockerfile].freeze

  DEFAULT_NODE_VERSION = "22"

  # Config vars these builders read inside the build (Dokku exports app config
  # into the build environment). Reconcile them so a service that is no longer
  # static does not keep injecting a publish directory.
  BUILD_ENV_KEYS = %w[
    NIXPACKS_NODE_VERSION
    NIXPACKS_SPA_OUT_DIR
    RAILPACK_NODE_VERSION
    RAILPACK_SPA_OUTPUT_DIR
  ].freeze

  # Railpack writes its Caddyfile to the image root; nixpacks copies generated
  # assets into /assets. RailDock's builder-detected port is exported as
  # Dokku's PORT, and both Caddyfiles listen on `{$PORT}`. The paths double as
  # the fingerprint of a static image, which is how a failed deploy recovers the
  # command the builder meant to run (see DeploymentJob).
  CADDY_CONFIG_PATHS = {
    "railpack" => "/Caddyfile",
    "nixpacks" => "/assets/Caddyfile"
  }.freeze

  SERVE_COMMANDS = CADDY_CONFIG_PATHS.transform_values do |path|
    "caddy run --config #{path} --adapter caddyfile"
  end.freeze

  # `detected_config` is the deploy-time detection (StaticSiteProbe) for services
  # that never had static settings saved. Explicit service config wins key by
  # key, so detection only fills in what the service does not declare.
  def initialize(service, detected_config: nil)
    @service = service
    @detected_config = detected_config
  end

  def static?
    return false unless service.service_type_app?
    return false if service.docker_image.present?
    return false if service.start_command.present?

    publish_directory.present?
  end

  def publish_directory
    static_config["publishDirectory"].presence
  end

  def spa_fallback?
    value = static_config["spaFallback"]
    value.nil? ? true : ActiveModel::Type::Boolean.new.cast(value)
  end

  def node_version
    static_config["nodeVersion"].presence
  end

  # Resolves the builder slug RailDock should use for this service.
  #
  # `available` is callable with a builder slug ("railpack"/"nixpacks") and
  # returns whether that builder is ready on the target server. Returns nil when
  # RailDock should leave the builder untouched.
  def resolve_builder(available:)
    return nil unless static?
    return nil if PASSTHROUGH_BUILDERS.include?(configured_builder)

    preferred_static_builder(available)
  end

  # True when the configured builder owns its own build and serve behavior, so
  # RailDock must not substitute one or treat a missing static builder as a
  # failure. A Dockerfile deploy always owns serving, even with a publish
  # directory set.
  def passthrough?
    return false unless static?

    PASSTHROUGH_BUILDERS.include?(configured_builder)
  end

  # True when the builder RailDock will use differs from the one configured
  # (including auto-detect), so the deploy can say which builder it picked.
  def builder_overridden?(resolved_builder)
    return false if resolved_builder.blank?

    configured_builder != resolved_builder
  end

  def build_env(builder)
    return {} unless static?
    return {} unless STATIC_BUILDERS.include?(builder)

    case builder
    when "railpack"
      env = { "RAILPACK_SPA_OUTPUT_DIR" => publish_directory }
      env["RAILPACK_NODE_VERSION"] = node_version if node_version.present?
      env
    when "nixpacks"
      {
        "NIXPACKS_SPA_OUT_DIR" => publish_directory,
        # Nixpacks hardcodes a default of Node 18, which is EOL and no longer
        # present in its pinned nixpkgs archives. Pin a supported LTS instead so
        # a frontend with no version pin still builds.
        "NIXPACKS_NODE_VERSION" => node_version.presence || DEFAULT_NODE_VERSION
      }
    end
  end

  def serve_command(builder)
    return nil unless static?

    SERVE_COMMANDS[builder]
  end

  private

  attr_reader :service

  def static_config
    @static_config ||= detected_config.merge(explicit_static_config)
  end

  def explicit_static_config
    value = service.config.is_a?(Hash) ? service.config["staticSite"] : nil
    value.is_a?(Hash) ? value : {}
  end

  def detected_config
    @detected_config.is_a?(Hash) ? @detected_config : {}
  end

  def configured_builder
    @configured_builder ||= service.builder.presence || "auto"
  end

  # Prefer railpack: it detects more static frameworks (CRA, Angular, Astro,
  # Next export, React Router) than nixpacks, whose Caddy SPA path only fires
  # for Vite. Fall back to nixpacks when railpack's BuildKit service is absent.
  def preferred_static_builder(available)
    return "railpack" if available.call("railpack")
    return "nixpacks" if available.call("nixpacks")

    nil
  end
end
