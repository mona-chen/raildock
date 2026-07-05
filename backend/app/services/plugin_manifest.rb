# frozen_string_literal: true

# Fetches and validates a RailDock plugin manifest from a remote source.
# Manifests may be YAML or JSON and define plugin metadata, service subtypes,
# builders, and a config schema.
class PluginManifest
  REQUIRED_PLUGIN_KEYS = %w[slug name category].freeze
  ALLOWED_CATEGORIES = %w[database cache queue search service tool].freeze

  attr_reader :url, :errors

  def initialize(url)
    @url = url
    @errors = []
  end

  # Returns a normalized manifest hash or nil when invalid.
  def fetch
    return nil if url.blank?

    response = Faraday.get(url) do |req|
      req.options.timeout = 30
      req.options.open_timeout = 10
    end

    unless response.success?
      @errors << "Could not fetch manifest: HTTP #{response.status}"
      return nil
    end

    parse(response.body)
  rescue Faraday::Error => e
    @errors << "Network error: #{e.message}"
    nil
  rescue => e
    @errors << "Unexpected error: #{e.message}"
    nil
  end

  def valid?
    @errors.empty?
  end

  private

  def parse(body)
    data =
      if url.end_with?(".json")
        JSON.parse(body)
      else
        YAML.safe_load(body, permitted_classes: [], permitted_symbols: [], aliases: true)
      end

    unless data.is_a?(Hash)
      @errors << "Manifest must be a JSON/YAML object"
      return nil
    end

    data = data.with_indifferent_access
    validate_structure(data)
    data
  rescue JSON::ParserError, Psych::SyntaxError => e
    @errors << "Parse error: #{e.message}"
    nil
  end

  def validate_structure(data)
    missing = REQUIRED_PLUGIN_KEYS - data.keys.map(&:to_s)
    @errors << "Missing required keys: #{missing.join(", ")}" if missing.any?

    unless ALLOWED_CATEGORIES.include?(data[:category].to_s)
      @errors << "Invalid category: #{data[:category]}"
    end

    subtypes = Array(data[:subtypes])
    builders = Array(data[:builders])

    if subtypes.empty? && builders.empty?
      @errors << "Manifest must define at least one subtype or builder"
    end

    subtypes.each_with_index do |st, i|
      missing_st = %w[subtype name service_type] - st.keys.map(&:to_s)
      @errors << "Subtype #{i + 1} missing: #{missing_st.join(", ")}" if missing_st.any?
    end

    builders.each_with_index do |b, i|
      missing_b = %w[slug name dokku_builder] - b.keys.map(&:to_s)
      @errors << "Builder #{i + 1} missing: #{missing_b.join(", ")}" if missing_b.any?
    end
  end
end
