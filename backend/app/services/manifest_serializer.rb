# frozen_string_literal: true

require "json"

# Serializes a canonical manifest — the normalized structure produced by
# ManifestParser — back into manifest file content.
#
# Drift merge (`ManifestDrift`) folds live values into the manifest and then
# needs to write the result back out, so the emitter has to be total: every
# canonical key must survive a parse → dump → parse round trip.
#
# Only RailDock-native manifests can be re-emitted. The compatibility formats
# (railway.toml, railway.json, app.json) map lossily onto the canonical form,
# so rewriting them would silently drop settings we cannot represent.
#
# The output is canonical: comments and formatting from the source file are not
# preserved, which is why merges are always returned for review rather than
# saved directly.
class ManifestSerializer
  class UnsupportedFormat < StandardError; end

  NATIVE_FORMATS = %w[raildock.toml raildock.json].freeze

  # Emitted in this order, straight onto the [[services]] table.
  SCALAR_KEYS = %i[
    name category subtype builder framework dockerfile_path version docker_image
    start_command root_directory publish_directory spa_fallback node_version
    exposed port maintenance restart_policy restart_max_retries auto_deploy
    source_revision
  ].freeze

  class << self
    def dump(desired, format: "raildock.toml", header: nil)
      format = format.to_s
      raise UnsupportedFormat, "#{format} cannot be regenerated" unless NATIVE_FORMATS.include?(format)

      if format.end_with?(".json")
        payload = {
          services: Array(desired[:services]).map { |service| prune(service) },
          links: Array(desired[:links]).map { |link| prune(link) }
        }
        return JSON.pretty_generate(payload) + "\n"
      end

      dump_toml(desired, header: header)
    end

    def dump_toml(desired, header: nil)
      lines = []
      Array(header).each { |line| lines << "# #{line}" }
      lines << "" if Array(header).any?

      Array(desired[:services]).each { |service| lines.concat(service_lines(service)) }
      Array(desired[:links]).each do |link|
        lines << "[[links]]"
        lines << "from = #{quote(link[:from])}"
        lines << "to = #{quote(link[:to])}"
        lines << ""
      end

      lines.join("\n").rstrip + "\n"
    end

    private

    # The parser reads an explicitly empty value as "configured", so a dump
    # carrying `"proxy": {}` or `"source": { "type": "git" }` comes back with
    # parser defaults attached. Drop anything that carries no information so a
    # dump → parse round trip is exact.
    def prune(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), result|
          next if entry.nil?

          source = entry.is_a?(Hash) ? entry.compact : nil
          if key.to_sym == :source
            next if source[:repo].blank? && source[:type].to_s == "git"

            result[key] = prune(source)
            next
          end

          pruned = prune(entry)
          next if pruned == {} || pruned == []

          result[key] = pruned
        end
      when Array
        value.reject(&:nil?).map { |entry| prune(entry) }
      else
        value
      end
    end

    def service_lines(service)
      lines = [ "[[services]]" ]
      SCALAR_KEYS.each do |key|
        value = service[key]
        lines << "#{key} = #{toml_value(value)}" unless value.nil?
      end

      source = service[:source]
      # A bare `{ type: "git" }` source is the parser's default for "no source
      # declared", and re-emitting it would make the parser add a `main` branch
      # that was never there. Only write it when it carries real information.
      source = source.compact if source.is_a?(Hash)
      if source.present? && (source[:repo].present? || source[:type].to_s != "git")
        pairs = source.map { |key, value| "#{key} = #{quote(value)}" }
        lines << "source = { #{pairs.join(', ')} }"
      end

      lines << "domains = #{toml_value(service[:domains])}" if service[:domains].present?
      lines << "depends_on = #{toml_value(service[:depends_on])}" if service[:depends_on].present?
      lines << "env = #{toml_value(service[:env])}" if service[:env].present?

      proxy = service[:proxy]
      if proxy.is_a?(Hash) && proxy.present?
        lines << ""
        lines << "[services.proxy]"
        lines << "enabled = #{proxy[:enabled] == false ? 'false' : 'true'}"
        lines << "type = #{quote(proxy[:type] || 'traefik')}"
        Array(proxy[:ports]).each do |port|
          lines << ""
          lines << "[[services.proxy.ports]]"
          lines << "host = #{port[:host].to_i}"
          lines << "container = #{port[:container].to_i}"
          lines << "scheme = #{quote(port[:scheme] || 'http')}"
        end
      end

      table(lines, "scaling", service[:scaling])
      table(lines, "limits", service[:limits])
      table(lines, "reservations", service[:reservations])
      checks(lines, service[:checks])
      array_table(lines, "cron", service[:cron], %i[command schedule])
      array_table(lines, "storage", service[:storage], %i[host container kind])
      array_table(lines, "docker_options", service[:docker_options], %i[phase option])
      table(lines, "traefik_labels", service[:traefik_labels])
      table(lines, "letsencrypt", service[:letsencrypt])

      lines << ""
      lines
    end

    def checks(lines, value)
      return unless value.is_a?(Hash) && value.present?

      lines << ""
      lines << "[services.checks]"
      lines << "enabled = #{value[:enabled] == true ? 'true' : 'false'}"
      %i[mode wait timeout attempts wait_to_retire path].each do |key|
        lines << "#{key} = #{toml_value(value[key])}" unless value[key].nil?
      end
      lines << "skip = #{toml_value(value[:skip])}" if value[:skip].present?
    end

    def table(lines, name, value)
      return unless value.is_a?(Hash) && value.present?

      lines << ""
      lines << "[services.#{name}]"
      value.each do |key, entry|
        next if entry.nil?

        lines << "#{toml_key(key)} = #{toml_value(entry)}"
      end
    end

    def array_table(lines, name, entries, keys)
      return unless entries.is_a?(Array) && entries.present?

      entries.each do |entry|
        next unless entry.is_a?(Hash)

        lines << ""
        lines << "[[services.#{name}]]"
        keys.each do |key|
          lines << "#{key} = #{toml_value(entry[key])}" unless entry[key].nil?
        end
      end
    end

    def toml_value(value)
      case value
      when true, false then value.to_s
      when Numeric then value.to_s
      when Array then "[#{value.map { |entry| toml_value(entry) }.join(', ')}]"
      when Hash
        pairs = value.map { |key, entry| "#{toml_key(key)} = #{toml_value(entry)}" }
        "{ #{pairs.join(', ')} }"
      else quote(value)
      end
    end

    def toml_key(key)
      key.to_s.match?(/\A[A-Za-z0-9_-]+\z/) ? key.to_s : quote(key)
    end

    def quote(value)
      %("#{value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}")
    end
  end
end
