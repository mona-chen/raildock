# frozen_string_literal: true

# Validates a hash of setting values against a schema definition.
# Schema shape: { "fieldKey" => { type: "string|number|integer|boolean|select", required: bool, options: [...], min: n, max: n, label: "..." } }
class ConfigSchema
  VALID_TYPES = %w[string number integer boolean select].freeze

  def self.validate(values, schema)
    new(values, schema).validate
  end

  def initialize(values, schema)
    @values = values || {}
    @schema = schema || {}
    @errors = []
  end

  def validate
    @schema.each do |key, field|
      field = field.with_indifferent_access
      raw_value = @values[key.to_s]

      if missing?(raw_value)
        @errors << "#{field[:label] || key} is required" if field[:required]
        next
      end

      type = field[:type].to_s
      unless VALID_TYPES.include?(type)
        @errors << "#{field[:label] || key} has unknown type #{type}"
        next
      end

      value = coerce_value(raw_value, type)

      validate_type(key, field, value, type)
      validate_range(key, field, value)
      validate_options(key, field, value)
    end

    @errors
  end

  private

  def missing?(value)
    return true if value.nil?
    return false if value == false

    value.respond_to?(:empty?) && value.empty?
  end

  def coerce_value(raw, type)
    case type
    when "boolean"
      case raw.to_s.downcase
      when "true", "1", "yes", "on" then true
      when "false", "0", "no", "off" then false
      else raw
      end
    when "number"
      Float(raw) rescue raw
    when "integer"
      Integer(raw, 10) rescue raw
    else
      raw
    end
  end

  def validate_type(key, field, value, type)
    case type
    when "boolean"
      @errors << "#{field[:label] || key} must be a boolean" unless value == true || value == false
    when "number"
      @errors << "#{field[:label] || key} must be a number" unless value.is_a?(Numeric)
    when "integer"
      @errors << "#{field[:label] || key} must be an integer" unless value.is_a?(Integer)
    end
  end

  def validate_range(key, field, value)
    return unless value.is_a?(Numeric)

    min = field[:min]
    max = field[:max]
    @errors << "#{field[:label] || key} must be at least #{min}" if min && value < min
    @errors << "#{field[:label] || key} must be at most #{max}" if max && value > max
  end

  def validate_options(key, field, value)
    options = field[:options]
    return unless options.is_a?(Array) && options.any?

    @errors << "#{field[:label] || key} must be one of #{options.join(", ")}" unless options.include?(value)
  end
end
