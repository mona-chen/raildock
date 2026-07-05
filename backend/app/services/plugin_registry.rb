# frozen_string_literal: true

# Boot-time registry for server-capability plugins and their service subtypes.
# Built-in plugins are seeded idempotently; the registry then provides runtime
# lookups used by DokkuEngine, controllers, and jobs instead of hard-coded
# `case service.subtype` branches.
class PluginRegistry
  APP_SUBTYPES = {
    "core-apps" => {
      name: "Core Applications",
      description: "Application process subtypes deployed from Git or Docker images.",
      category: "tool",
      icon: "rocket",
      status: "built_in",
      subtypes: [
        {
          subtype: "web",
          name: "Web Service",
          description: "Long-running process exposed to the internet via the proxy",
          service_type: "app",
          dokku_plugin: nil,
          default_version: "",
          icon: "globe",
          color: "#8b5cf6",
          capabilities: %w[deploy scale metrics domain proxy],
          env_var_prefix: nil,
          metadata: {}
        },
        {
          subtype: "worker",
          name: "Worker",
          description: "Background process with no exposed ports",
          service_type: "app",
          dokku_plugin: nil,
          default_version: "",
          icon: "cpu",
          color: "#8b5cf6",
          capabilities: %w[deploy scale logs metrics],
          env_var_prefix: nil,
          metadata: {}
        },
        {
          subtype: "docker",
          name: "Docker Image",
          description: "Deploy a pre-built container image directly",
          service_type: "app",
          dokku_plugin: nil,
          default_version: "",
          icon: "container",
          color: "#8b5cf6",
          capabilities: %w[deploy scale metrics domain proxy],
          env_var_prefix: nil,
          metadata: {}
        }
      ]
    }
  }.freeze

  BUILDERS = {
    "core-builders" => {
      name: "Core Builders",
      description: "Default container build strategies for Git-based apps.",
      category: "tool",
      icon: "hammer",
      status: "built_in",
      builders: [
        {
          slug: "auto",
          name: "Auto-detect",
          description: "Dokku checks for Dockerfile → Nixpacks → Herokuish in that order.",
          dokku_builder: "auto",
          source_types: %w[git],
          priority: 0,
          language_tags: %w[],
          icon: "wand-2",
          color: "#6b7280",
          config_schema: {}
        },
        {
          slug: "dockerfile",
          name: "Dockerfile",
          description: "Builds your container using the Dockerfile in your repo root.",
          dokku_builder: "dockerfile",
          source_types: %w[git],
          priority: 10,
          language_tags: %w[],
          icon: "file-code",
          color: "#3b82f6",
          config_schema: {}
        },
        {
          slug: "nixpacks",
          name: "Nixpacks",
          description: "Auto-detects language and produces optimized images without a Dockerfile.",
          dokku_builder: "nixpacks",
          source_types: %w[git],
          priority: 20,
          language_tags: %w[node python go ruby php rust java dotnet],
          icon: "package",
          color: "#f59e0b",
          config_schema: {}
        },
        {
          slug: "railpack",
          name: "Railpack",
          description: "Railway-inspired buildpack with modern language support.",
          dokku_builder: "railpack",
          source_types: %w[git],
          priority: 30,
          language_tags: %w[node python go ruby rust],
          icon: "train-front",
          color: "#10b981",
          config_schema: {}
        },
        {
          slug: "herokuish",
          name: "Herokuish",
          description: "Emulates Heroku buildpacks using the same detection logic.",
          dokku_builder: "herokuish",
          source_types: %w[git],
          priority: 40,
          language_tags: %w[node ruby python php go java],
          icon: "box",
          color: "#6366f1",
          config_schema: {}
        },
        {
          slug: "pack",
          name: "Cloud Native Buildpacks",
          description: "Uses the cloud-native buildpack standard (Paketo, etc).",
          dokku_builder: "pack",
          source_types: %w[git],
          priority: 50,
          language_tags: %w[node python go ruby php java dotnet],
          icon: "cloud",
          color: "#0ea5e9",
          config_schema: {}
        },
        {
          slug: "lambda",
          name: "Lambda",
          description: "AWS Lambda-style packaging for serverless deployments.",
          dokku_builder: "lambda",
          source_types: %w[git],
          priority: 60,
          language_tags: %w[node python ruby go java],
          icon: "zap",
          color: "#f97316",
          config_schema: {}
        },
        {
          slug: "null",
          name: "Null Builder",
          description: "Skip build, use existing image.",
          dokku_builder: "null",
          source_types: %w[docker],
          priority: 70,
          language_tags: %w[],
          icon: "ban",
          color: "#6b7280",
          config_schema: {}
        }
      ]
    }
  }.freeze

  BUILT_INS = {
    "core-databases" => {
      name: "Core Databases",
      description: "Relational and document databases managed by Dokku.",
      category: "database",
      icon: "database",
      status: "built_in",
      subtypes: [
        {
          subtype: "postgres",
          name: "PostgreSQL",
          description: "Relational database",
          service_type: "database",
          dokku_plugin: "postgres",
          default_version: "16",
          icon: "postgres",
          color: "#336791",
          capabilities: %w[create destroy link unlink info logs backup restore export point_in_time_recovery],
          env_var_prefix: "DATABASE_URL",
          metadata: {
            url_scheme: "postgres",
            sslmode: "disable"
          }
        },
        {
          subtype: "mysql",
          name: "MySQL",
          description: "Popular relational database",
          service_type: "database",
          dokku_plugin: "mysql",
          default_version: "8.0",
          icon: "mysql",
          color: "#4479A1",
          capabilities: %w[create destroy link unlink info logs backup restore export],
          env_var_prefix: "DATABASE_URL",
          metadata: {
            url_scheme: "mysql"
          }
        },
        {
          subtype: "mariadb",
          name: "MariaDB",
          description: "Community-developed fork of MySQL",
          service_type: "database",
          dokku_plugin: "mysql",
          command_namespace: "mysql",
          default_version: "10.11",
          icon: "mariadb",
          color: "#003545",
          capabilities: %w[create destroy link unlink info logs backup restore export],
          env_var_prefix: "DATABASE_URL",
          metadata: {
            url_scheme: "mysql"
          }
        },
        {
          subtype: "mongo",
          name: "MongoDB",
          description: "Document NoSQL database",
          service_type: "database",
          dokku_plugin: "mongo",
          default_version: "7.0",
          icon: "mongo",
          color: "#47A248",
          capabilities: %w[create destroy link unlink info logs backup restore export],
          env_var_prefix: "MONGO_URL",
          metadata: {
            url_scheme: "mongodb"
          }
        }
      ]
    },
    "core-cache" => {
      name: "Core Cache",
      description: "In-memory caches and session stores.",
      category: "cache",
      icon: "zap",
      status: "built_in",
      subtypes: [
        {
          subtype: "redis",
          name: "Redis",
          description: "In-memory key-value store",
          service_type: "cache",
          dokku_plugin: "redis",
          default_version: "7.2",
          icon: "redis",
          color: "#DC382D",
          capabilities: %w[create destroy link unlink info logs backup restore export],
          env_var_prefix: "REDIS_URL",
          metadata: {
            url_scheme: "redis"
          }
        }
      ]
    },
    "core-services" => {
      name: "Core Services",
      description: "Common one-click services and message brokers.",
      category: "service",
      icon: "cog",
      status: "built_in",
      subtypes: [
        {
          subtype: "rabbitmq",
          name: "RabbitMQ",
          description: "Message broker and queue system",
          service_type: "queue",
          dokku_plugin: nil,
          default_version: "latest",
          icon: "rabbitmq",
          color: "#FF6600",
          capabilities: %w[docker_deploy],
          metadata: {
            default_image: "rabbitmq:alpine"
          }
        },
        {
          subtype: "minio",
          name: "MinIO",
          description: "S3-compatible object storage",
          service_type: "service",
          dokku_plugin: nil,
          default_version: "latest",
          icon: "minio",
          color: "#C72C48",
          capabilities: %w[docker_deploy],
          metadata: {
            default_image: "minio/minio:latest"
          }
        },
        {
          subtype: "elasticsearch",
          name: "Elasticsearch",
          description: "Distributed search and analytics engine",
          service_type: "search",
          dokku_plugin: nil,
          default_version: "8",
          icon: "elasticsearch",
          color: "#005571",
          capabilities: %w[docker_deploy],
          metadata: {
            default_image: "elasticsearch:8"
          }
        },
        {
          subtype: "meilisearch",
          name: "Meilisearch",
          description: "Lightning-fast search engine",
          service_type: "search",
          dokku_plugin: nil,
          default_version: "latest",
          icon: "search",
          color: "#3b82f6",
          capabilities: %w[docker_deploy],
          metadata: {
            default_image: "getmeili/meilisearch:latest"
          }
        },
        {
          subtype: "typesense",
          name: "Typesense",
          description: "Open-source typo-tolerant search engine",
          service_type: "search",
          dokku_plugin: nil,
          default_version: "latest",
          icon: "search",
          color: "#3b82f6",
          capabilities: %w[docker_deploy],
          metadata: {
            default_image: "typesense/typesense:latest"
          }
        }
      ]
    }
  }.freeze

  class << self
    def seed!
      seed_plugins_and_subtypes!(APP_SUBTYPES)
      seed_plugins_and_subtypes!(BUILT_INS)
      seed_builders!(BUILDERS)
    end

    def seed_plugins_and_subtypes!(collection)
      collection.each do |slug, attrs|
        attrs = attrs.dup
        subtypes = attrs.delete(:subtypes) || []
        plugin = Plugin.find_or_initialize_by(slug: slug)
        plugin.assign_attributes(attrs)
        plugin.save!

        subtypes.each do |subtype_attrs|
          st = plugin.service_subtypes.find_or_initialize_by(subtype: subtype_attrs[:subtype])
          st.assign_attributes(subtype_attrs)
          st.save!
        end
      end
    end

    def seed_builders!(collection)
      collection.each do |slug, attrs|
        attrs = attrs.dup
        builders = attrs.delete(:builders) || []
        plugin = Plugin.find_or_initialize_by(slug: slug)
        plugin.assign_attributes(attrs)
        plugin.save!

        builders.each do |builder_attrs|
          b = plugin.builders.find_or_initialize_by(slug: builder_attrs[:slug])
          b.assign_attributes(builder_attrs)
          b.save!
        end
      end
    end

    # Register or update an external plugin from an install manifest.
    def register_external!(manifest)
      manifest = manifest.with_indifferent_access
      slug = manifest[:slug]
      return false if slug.blank?

      plugin_attrs = manifest.slice(
        :name, :description, :category, :icon, :version, :config_schema, :metadata,
        :source_type, :source_url, :source_ref, :install_command, :uninstall_command
      )

      plugin = Plugin.find_or_initialize_by(slug: slug)
      plugin.assign_attributes(plugin_attrs)
      plugin.status = "enabled" unless plugin.built_in?
      plugin.save!

      Array(manifest[:subtypes]).each do |st|
        st = st.with_indifferent_access
        subtype = plugin.service_subtypes.find_or_initialize_by(subtype: st[:subtype])
        subtype.assign_attributes(st)
        subtype.save!
      end

      Array(manifest[:builders]).each do |b|
        b = b.with_indifferent_access
        builder = plugin.builders.find_or_initialize_by(slug: b[:slug])
        builder.assign_attributes(b)
        builder.status = "enabled" unless builder.built_in?
        builder.save!
      end

      plugin
    end

    def unregister!(plugin)
      return false if plugin.built_in?

      plugin.destroy!
      true
    end

    def find_subtype(subtype)
      return nil if subtype.blank?

      Rails.cache.fetch("plugin_registry/subtype/#{subtype.to_s.downcase}", expires_in: 5.minutes) do
        ServiceSubtype.find_by(subtype: subtype.to_s.downcase)
      end
    end

    def find_builder(slug)
      return nil if slug.blank?

      Rails.cache.fetch("plugin_registry/builder/#{slug.to_s.downcase}", expires_in: 5.minutes) do
        Builder.find_by(slug: slug.to_s.downcase)
      end
    end

    def find_plugin(slug)
      Plugin.find_by(slug: slug.to_s)
    end

    def subtypes_for(service_type)
      ServiceSubtype.for_service_type(service_type).order(:name)
    end

    def builders_for(source_type = nil)
      scope = Builder.enabled.order(:priority)
      source_type ? scope.for_source_type(source_type) : scope
    end

    def default_builder_for(service_subtype, source_type = "git")
      builders_for(source_type).first
    end

    def plugins
      Plugin.enabled.includes(:service_subtypes, :builders).order(:name)
    end

    def capabilities_for(subtype)
      find_subtype(subtype)&.capabilities || []
    end

    def has_capability?(subtype, capability)
      find_subtype(subtype)&.has_capability?(capability) || false
    end

    def clear_cache!
      ServiceSubtype.pluck(:subtype).each do |subtype|
        Rails.cache.delete("plugin_registry/subtype/#{subtype}")
      end
      Builder.pluck(:slug).each do |slug|
        Rails.cache.delete("plugin_registry/builder/#{slug}")
      end
    end
  end
end
