# frozen_string_literal: true

# Boot-time registry for server-capability plugins and their service subtypes.
# Built-in plugins are seeded idempotently; the registry then provides runtime
# lookups used by DokkuEngine, controllers, and jobs instead of hard-coded
# `case service.subtype` branches.
class PluginRegistry
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
      BUILT_INS.each do |slug, attrs|
        attrs = attrs.dup
        subtypes = attrs.delete(:subtypes)
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

    def find_subtype(subtype)
      return nil if subtype.blank?

      Rails.cache.fetch("plugin_registry/subtype/#{subtype.to_s.downcase}", expires_in: 5.minutes) do
        ServiceSubtype.find_by(subtype: subtype.to_s.downcase)
      end
    end

    def find_plugin(slug)
      Plugin.find_by(slug: slug.to_s)
    end

    def subtypes_for(service_type)
      ServiceSubtype.for_service_type(service_type).order(:name)
    end

    def plugins
      Plugin.enabled.includes(:service_subtypes).order(:name)
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
    end
  end
end
