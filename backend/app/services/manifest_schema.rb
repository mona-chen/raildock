# frozen_string_literal: true

# Lightweight schema validation for manifest files.
# Uses a declarative hash schema that works for both JSON and TOML-derived hashes.
class ManifestSchema
  class ValidationResult
    attr_reader :valid, :errors

    def initialize(valid:, errors: [])
      @valid = valid
      @errors = errors
    end

    def success?
      @valid
    end
  end

  SERVICE_TYPES = %w[app database cache queue search service].freeze
  PROXY_TYPES = %w[traefik caddy nginx].freeze
  BUILDERS = %w[herokuish pack dockerfile nixpacks railpack lambda null].freeze

  def self.validate(hash)
    new.validate(hash)
  end

  def validate(hash)
    errors = []

    unless hash.is_a?(Hash)
      return ValidationResult.new(valid: false, errors: [ "Manifest must be an object/hash" ])
    end

    # app.json has a different top-level structure
    if app_json?(hash)
      errors.concat(validate_app_json(hash))
    elsif railway?(hash)
      errors.concat(validate_railway(hash))
    else
      errors.concat(validate_raildock(hash))
    end

    ValidationResult.new(valid: errors.empty?, errors: errors)
  end

  private

  def app_json?(hash)
    hash.key?("buildpacks") || hash.key?("formation") || hash.key?("stack")
  end

  # Railway's signature top-level keys are build and deploy. If both are
  # present (or either one is), we route to validate_railway. raildock.toml
  # has neither, so there's no ambiguity.
  def railway?(hash)
    hash.key?("build") || hash.key?("deploy")
  end

  def validate_app_json(hash)
    errors = []
    errors << "app.json: 'name' must be a string" if hash["name"] && !hash["name"].is_a?(String)
    errors << "app.json: 'buildpacks' must be an array" if hash["buildpacks"] && !hash["buildpacks"].is_a?(Array)
    errors << "app.json: 'formation' must be an object" if hash["formation"] && !hash["formation"].is_a?(Hash)
    errors << "app.json: 'env' must be an object" if hash["env"] && !hash["env"].is_a?(Hash)
    errors << "app.json: 'cron' must be an array" if hash["cron"] && !hash["cron"].is_a?(Array)
    errors
  end

  def validate_railway(hash)
    errors = []
    prefix = "railway"

    # build section
    if hash.key?("build")
      unless hash["build"].is_a?(Hash)
        errors << "#{prefix}: 'build' must be an object"
      else
        if hash["build"].key?("builder") && !hash["build"]["builder"].is_a?(String)
          errors << "#{prefix}.build.builder: must be a string"
        end
        if hash["build"].key?("buildCommand") && !hash["build"]["buildCommand"].is_a?(String)
          errors << "#{prefix}.build.buildCommand: must be a string"
        end
      end
    end

    # deploy section
    if hash.key?("deploy")
      unless hash["deploy"].is_a?(Hash)
        errors << "#{prefix}: 'deploy' must be an object"
      else
        if hash["deploy"].key?("startCommand") && !hash["deploy"]["startCommand"].is_a?(String) && !hash["deploy"]["startCommand"].is_a?(Array)
          errors << "#{prefix}.deploy.startCommand: must be a string or array"
        end
        if hash["deploy"].key?("healthcheckPath") && !hash["deploy"]["healthcheckPath"].is_a?(String)
          errors << "#{prefix}.deploy.healthcheckPath: must be a string"
        end
        if hash["deploy"].key?("healthcheckTimeout") && !hash["deploy"]["healthcheckTimeout"].is_a?(Integer)
          errors << "#{prefix}.deploy.healthcheckTimeout: must be an integer"
        end
        if hash["deploy"].key?("restartPolicyType") && !%w[never on-failure always].include?(hash["deploy"]["restartPolicyType"].to_s)
          errors << "#{prefix}.deploy.restartPolicyType: must be one of: never, on-failure, always"
        end
        if hash["deploy"].key?("preDeployCommand") && !hash["deploy"]["preDeployCommand"].is_a?(String) && !hash["deploy"]["preDeployCommand"].is_a?(Array)
          errors << "#{prefix}.deploy.preDeployCommand: must be a string or array"
        end
      end
    end

    # env and vars sections
    if hash.key?("env") && !hash["env"].is_a?(Hash)
      errors << "#{prefix}: 'env' must be an object"
    end
    if hash.key?("vars") && !hash["vars"].is_a?(Hash)
      errors << "#{prefix}: 'vars' must be an object"
    end

    errors
  end

  def validate_raildock(hash)
    errors = []

    unless hash["services"].is_a?(Array)
      errors << "raildock: 'services' must be an array"
      return errors
    end

    if hash["services"].empty?
      errors << "raildock: 'services' cannot be empty"
    end

    hash["services"].each_with_index do |svc, idx|
      errors.concat(validate_service(svc, idx))
    end

    if hash["links"].is_a?(Array)
      hash["links"].each_with_index do |link, idx|
        errors.concat(validate_link(link, idx))
      end
    end

    errors
  end

  def validate_service(svc, idx)
    errors = []
    prefix = "services[#{idx}]"

    errors << "#{prefix}: 'name' is required" if svc["name"].blank?
    errors << "#{prefix}: 'name' must be a string" if svc["name"] && !svc["name"].is_a?(String)

    if svc["category"] && !SERVICE_TYPES.include?(svc["category"].to_s)
      errors << "#{prefix}: 'category' must be one of: #{SERVICE_TYPES.join(', ')}"
    end

    if svc["builder"] && !BUILDERS.include?(svc["builder"].to_s)
      errors << "#{prefix}: 'builder' must be one of: #{BUILDERS.join(', ')}"
    end

    if svc["proxy"].is_a?(Hash)
      if svc["proxy"]["type"] && !PROXY_TYPES.include?(svc["proxy"]["type"].to_s)
        errors << "#{prefix}.proxy: 'type' must be one of: #{PROXY_TYPES.join(', ')}"
      end
      if svc["proxy"]["ports"].is_a?(Array)
        svc["proxy"]["ports"].each_with_index do |port, pidx|
          unless port.is_a?(Hash) && (port["host"] || port["container"])
            errors << "#{prefix}.proxy.ports[#{pidx}]: must have 'host' and/or 'container'"
          end
        end
      end
    end

    if svc["scaling"].is_a?(Hash)
      svc["scaling"].each do |k, v|
        errors << "#{prefix}.scaling.#{k}: must be an integer" unless v.is_a?(Integer) || v.to_s.match?(/^\d+$/)
      end
    end

    if svc["env"].is_a?(Hash)
      svc["env"].each do |k, v|
        errors << "#{prefix}.env.#{k}: env values must be strings" unless v.is_a?(String)
      end
    elsif svc["env"]
      errors << "#{prefix}: 'env' must be an object"
    end

    if svc["cron"].is_a?(Array)
      svc["cron"].each_with_index do |c, cidx|
        if c.is_a?(Hash)
          errors << "#{prefix}.cron[#{cidx}]: 'command' is required" if c["command"].blank?
          errors << "#{prefix}.cron[#{cidx}]: 'schedule' is required" if c["schedule"].blank?
        else
          errors << "#{prefix}.cron[#{cidx}]: must be an object"
        end
      end
    elsif svc["cron"]
      errors << "#{prefix}: 'cron' must be an array"
    end

    errors
  end

  def validate_link(link, idx)
    errors = []
    prefix = "links[#{idx}]"
    errors << "#{prefix}: 'from' is required" if link["from"].blank?
    errors << "#{prefix}: 'to' is required" if link["to"].blank?
    errors
  end
end
