# frozen_string_literal: true

require "json"

# Detects whether a JavaScript project builds to a static bundle, and where the
# bundle lands.
#
# The rules mirror Railpack's SPA provider (core/providers/node/{spa,vite,cra,
# astro,angular,next}.go) so a repo that deploys as a static site on Railway
# deploys the same way through RailDock. Detection is deliberately conservative:
# frameworks whose default build is a server (SvelteKit, Nuxt, Astro with an
# adapter, Next without `output: "export"`) are left alone.
class StaticSiteDetector
  # `start` scripts that are development servers, not a production process.
  # Their presence must not disqualify a framework (a CRA app always has one).
  DEFAULT_START_COMMANDS = [
    "ng serve",
    "react-scripts start",
    "expo start",
    "next start",
    "next dev",
    "vite preview",
    "vue-cli-service serve"
  ].freeze

  # Frameworks that need a Node server unless explicitly configured for a
  # static export. Matched against dependencies.
  SERVER_FRAMEWORKS = %w[
    @sveltejs/kit
    nuxt
    @tanstack/react-start
  ].freeze

  # Framework config files that can override a default publish directory. Kept
  # here so import-time discovery (RepositoryDiscovery) and deploy-time probing
  # (StaticSiteProbe) read exactly the same inputs.
  CONFIG_FILES = %w[
    vite.config.js vite.config.ts vite.config.mjs vite.config.mts
    angular.json
    astro.config.js astro.config.mjs astro.config.ts
    next.config.js next.config.mjs next.config.ts
    svelte.config.js gatsby-config.js gatsby-config.ts
  ].freeze

  Result = Data.define(:framework, :publish_directory, :spa_fallback, :node_version) do
    # The shape service.config["staticSite"] uses, so a detection result can be
    # handed straight to StaticSiteConfigurator.
    def config
      {
        "publishDirectory" => publish_directory,
        "spaFallback" => spa_fallback,
        "nodeVersion" => node_version
      }.compact
    end
  end

  def self.detect(package_json:, files: {})
    new(package_json: package_json, files: files).detect
  end

  def initialize(package_json:, files: {})
    @package_json = package_json.is_a?(Hash) ? package_json : {}
    @files = files || {}
  end

  def detect
    return nil if custom_start_command?
    return nil if server_framework?

    framework, directory = detect_framework
    return nil if framework.to_s.empty? || directory.to_s.empty?

    Result.new(
      framework: framework,
      publish_directory: directory,
      spa_fallback: true,
      node_version: detected_node_version
    )
  end

  private

  attr_reader :package_json, :files

  def dependencies
    @dependencies ||= %w[dependencies devDependencies peerDependencies].flat_map do |key|
      (package_json[key] || {}).keys
    end.uniq
  end

  def scripts
    @scripts ||= package_json["scripts"].is_a?(Hash) ? package_json["scripts"] : {}
  end

  def build_script
    scripts["build"].to_s.downcase
  end

  def custom_start_command?
    start = scripts["start"].to_s.strip
    return false if start.empty?

    !DEFAULT_START_COMMANDS.include?(start.downcase)
  end

  def server_framework?
    return true if dependencies.include?("@sveltejs/kit") && !adapter_static?

    dependencies.any? { |dep| SERVER_FRAMEWORKS.include?(dep) }
  end

  def adapter_static?
    dependencies.any? { |dep| dep == "@sveltejs/adapter-static" }
  end

  def detect_framework
    return [ "next", "out" ] if next_static_export?
    return [ "vite", vite_output_directory ] if vite?
    angular_directory = angular? ? angular_output_directory : nil
    return [ "angular", angular_directory ] if angular_directory.to_s.empty? == false
    return [ "cra", "build" ] if cra?
    return [ "gatsby", "public" ] if gatsby?
    return [ "astro", "dist" ] if astro_static?
    return [ "vue-cli", "dist" ] if vue_cli?
    return [ "sveltekit", "build" ] if adapter_static?

    [ nil, nil ]
  end

  def vite?
    return false unless dependencies.include?("vite") && scripts.key?("build")
    return false if dependencies.include?("@tanstack/react-start")
    return false if dependencies.include?("@sveltejs/kit")

    build_script.include?("vite build") || file_present?("vite.config.js", "vite.config.ts", "vite.config.mjs")
  end

  def vite_output_directory
    config = file_content("vite.config.js", "vite.config.ts", "vite.config.mjs")
    if (match = config.match(/outDir['"]?\s*:\s*['"]([^'"]+)['"]/))
      return match[1]
    end

    if (match = scripts["build"].to_s.match(/vite\s+build\b[^&|;]*?--outDir[=\s]+([^\s&|;]+)/))
      return match[1]
    end

    "dist"
  end

  def cra?
    dependencies.include?("react-scripts") && build_script.include?("react-scripts build")
  end

  def angular?
    dependencies.include?("@angular/core") && file_present?("angular.json") && build_script.include?("ng build")
  end

  def angular_output_directory
    config = parse_json(file_content("angular.json"))
    return nil unless config.is_a?(Hash)

    projects = config["projects"]
    return nil unless projects.is_a?(Hash)

    project = projects.values.first
    options = project.dig("architect", "build", "options") || project.dig("targets", "build", "options")
    return nil unless options.is_a?(Hash)

    output = options["outputPath"].to_s.strip
    return nil if output.empty?

    builder = project.dig("architect", "build", "builder") || project.dig("targets", "build", "builder")
    browser_field = options["browser"].to_s
    application_builder = builder.to_s.include?("build-angular:application") || !browser_field.empty?
    application_builder ? File.join(output, "browser") : output
  end

  def next_static_export?
    return false unless dependencies.include?("next")

    config = file_content("next.config.js", "next.config.mjs", "next.config.ts")
    config.match?(/output\s*:\s*['"]export['"]/)
  end

  def gatsby?
    dependencies.include?("gatsby") && build_script.include?("gatsby build")
  end

  def astro_static?
    return false unless dependencies.include?("astro") && build_script.include?("astro build")
    return false if dependencies.any? { |dep| dep.start_with?("@astrojs/") && dep != "@astrojs/sitemap" }

    true
  end

  def vue_cli?
    dependencies.include?("@vue/cli-service") && scripts.key?("build")
  end

  def detected_node_version
    raw = (package_json["engines"] || {})["node"].to_s
    return nil if raw.strip.empty?

    major = raw[/\d+/]
    major&.empty? ? nil : major
  end

  def file_present?(*names)
    names.any? { |name| files.key?(name) || files.keys.any? { |path| File.basename(path) == name } }
  end

  def file_content(*names)
    names.each do |name|
      direct = files[name]
      return direct if direct

      found = files.find { |path, _| File.basename(path) == name }
      return found[1] if found
    end
    ""
  end

  def parse_json(content)
    return nil if content.to_s.empty?

    JSON.parse(content)
  rescue JSON::ParserError
    nil
  end
end
