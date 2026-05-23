# frozen_string_literal: true

# Loads stack templates from git-backed directories.
#
# Templates are TOML files stored on disk. By default they live in:
#   backend/config/templates/
#
# Community templates can be sourced from a separate git repo configured via:
#   ENV['RAILDOCK_TEMPLATES_REPO'] = "https://github.com/raildock/templates.git"
#
# On boot, TemplateLoader:
# 1. Scans built-in templates from config/templates/
# 2. If a remote repo is configured, clones/updates it to tmp/raildock-templates/
# 3. Scans remote templates and merges them (remote takes precedence on ID conflict)
# 4. Validates each template against the manifest schema
# 5. Caches the result in memory (refreshed on Rails reload)
#
# Community workflow:
#   1. User forks the templates repo
#   2. Adds a new .toml file
#   3. Opens a PR
#   4. On merge, RailDock instances pull the repo on next restart
class TemplateLoader
  BUILTIN_DIR = Rails.root.join("config", "templates").to_s
  REMOTE_DIR = Rails.root.join("tmp", "raildock-templates").to_s

  class Template
    attr_reader :id, :name, :description, :category, :services, :links, :source, :raw, :warnings, :errors, :logo

    def initialize(attrs = {})
      @id = attrs[:id]
      @name = attrs[:name]
      @description = attrs[:description]
      @category = attrs[:category] || "stack"
      @services = attrs[:services] || []
      @links = attrs[:links] || []
      @source = attrs[:source] || "builtin"
      @raw = attrs[:raw]
      @warnings = attrs[:warnings] || []
      @errors = attrs[:errors] || []
      @logo = attrs[:logo]
    end

    def valid?
      @errors.empty?
    end

    def to_h
      {
        id: @id,
        name: @name,
        description: @description,
        category: @category,
        services: @services,
        links: @links,
        source: @source,
        raw: @raw,
        logo: @logo,
        valid: valid?,
        warnings: @warnings,
        errors: @errors
      }
    end
  end

  class << self
    def all
      @templates ||= load_all
    end

    def find(id)
      all.find { |t| t.id == id }
    end

    def by_category(category)
      all.select { |t| t.category == category }
    end

    def refresh!
      @templates = load_all
    end

    private

    def load_all
      templates = {}

      # Built-in templates first
      load_from_dir(BUILTIN_DIR, "builtin").each do |t|
        templates[t.id] = t
      end

      # Remote / community templates override built-ins on ID conflict
      remote_repo = ENV["RAILDOCK_TEMPLATES_REPO"]
      if remote_repo.present?
        sync_remote_repo(remote_repo)
        load_from_dir(REMOTE_DIR, "community").each do |t|
          templates[t.id] = t
        end
      end

      templates.values.sort_by(&:name)
    end

    def load_from_dir(dir, source)
      return [] unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*.toml")).sort.map do |path|
        load_template_file(path, source)
      end.compact
    end

    def load_template_file(path, source)
      raw = File.read(path)
      hash = TomlRB.parse(raw)

      id = File.basename(path, ".toml")
      name = hash["name"] || id.humanize
      description = hash["description"] || ""
      category = hash["category"] || "stack"
      logo = hash["logo"] || nil
      logo_url = resolve_logo_url(id, logo)

      # Validate against manifest schema (raildock format)
      validation = ManifestSchema.validate(hash)

      # Parse services and links using the same parser logic
      desired = ManifestParser.parse(raw, filename: "raildock.toml")

      Template.new(
        id: id,
        name: name,
        description: description,
        category: category,
        services: desired.services,
        links: desired.links,
        source: source,
        raw: raw,
        logo: logo_url,
        warnings: desired.warnings,
        errors: validation.errors
      )
    rescue => e
      Rails.logger.error "Failed to load template #{path}: #{e.message}"
      Template.new(
        id: id || File.basename(path, ".toml"),
        name: name || File.basename(path, ".toml").humanize,
        description: description || "",
        source: source,
        raw: raw,
        errors: ["Failed to parse: #{e.message}"]
      )
    end

    def resolve_logo_url(id, logo_path)
      return nil unless logo_path

      # Look for logo file in public/templates/logos/{id}.*
      logo_dir = Rails.public_path.join("templates", "logos")
      matches = Dir.glob(logo_dir.join("#{id}.*"))
      return nil if matches.empty?

      ext = File.extname(matches.first)
      "/templates/logos/#{id}#{ext}"
    end

    def sync_remote_repo(repo_url)
      if Dir.exist?(File.join(REMOTE_DIR, ".git"))
        # Pull latest
        system("git -C #{REMOTE_DIR} pull --depth 1 --quiet")
      else
        # Clone fresh
        FileUtils.rm_rf(REMOTE_DIR)
        FileUtils.mkdir_p(REMOTE_DIR)
        system("git clone --depth 1 #{repo_url} #{REMOTE_DIR} --quiet")
      end
    rescue => e
      Rails.logger.error "Failed to sync remote templates repo: #{e.message}"
    end
  end
end
