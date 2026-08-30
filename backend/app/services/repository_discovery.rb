# frozen_string_literal: true

class RepositoryDiscovery
  MANIFEST_NAMES = %w[raildock.toml raildock.json railway.toml railway.json app.json].freeze
  CONVENTIONAL_NAMES = %w[Dockerfile Procfile package.json Gemfile].freeze
  MAX_DISCOVERY_FILES = 50

  Result = Data.define(:repository, :branch, :commit_sha, :services, :links, :warnings, :conflicts, :evidence, :original_format, :original_content) do
    def canonical_manifest
      JSON.pretty_generate({ name: repository.split("/").last, services: services, links: links })
    end

    def as_json(*)
      {
        repository: repository,
        branch: branch,
        commit_sha: commit_sha,
        services: services,
        links: links,
        warnings: warnings,
        conflicts: conflicts,
        evidence: evidence,
        canonical_manifest: canonical_manifest,
        format: original_format || "raildock.json"
      }
    end
  end

  def initialize(git_source:, repository:, branch: nil, client: nil)
    @git_source = git_source
    @repository = Service.repo_full_name(repository)
    @branch = branch.presence || repo_metadata&.fetch("default_branch", nil) || "main"
    @client = client || GithubAppService.installation_client(git_source.installation_id)
  end

  def call
    unless @git_source.github_app?
      raise ManifestParser::ParseError, "Automatic repository setup currently requires a connected GitHub App account"
    end
    raise ManifestParser::ParseError, "Repository is not available through this Git source" unless repository_allowed?

    commit_sha = resolve_commit_sha
    paths = repository_paths(commit_sha)
    native = paths.select { |path| %w[raildock.toml raildock.json].include?(File.basename(path)) }
    candidates = native.any? ? authoritative_native(native) : foreign_candidates(paths)

    services, links, warnings, evidence, original_format, original_content = compose_candidates(candidates, commit_sha)
    warnings.concat(superseded_manifest_warnings(native, paths))
    if services.empty?
      services, conventional_evidence, original_format, original_content = conventional_services(paths, commit_sha)
      evidence.concat(conventional_evidence)
    end

    raise ManifestParser::ParseError, "No deployable services were discovered" if services.empty?

    Result.new(
      repository: @repository,
      branch: @branch,
      commit_sha: commit_sha,
      services: unique_service_names(services),
      links: links,
      warnings: warnings,
      conflicts: [],
      evidence: evidence,
      original_format: original_format,
      original_content: original_content
    )
  end

  private
    def repo_metadata
      @repo_metadata ||= @git_source.repos.find do |repo|
        Service.repo_full_name(repo["full_name"] || repo[:full_name] || repo["clone_url"] || repo[:clone_url]) == @repository
      end
    end

    def repository_allowed?
      @repository.present? && repo_metadata.present?
    end

    def resolve_commit_sha
      @client.branch(@repository, @branch).commit.sha
    rescue Octokit::NotFound
      raise ManifestParser::ParseError, "Branch '#{@branch}' was not found"
    end

    def repository_paths(commit_sha)
      tree = @client.tree(@repository, commit_sha, recursive: true)
      raise ManifestParser::ParseError, "Repository is too large to inspect safely" if tree.truncated

      tree.tree.filter_map do |entry|
        next unless entry.type == "blob"
        next unless (MANIFEST_NAMES + CONVENTIONAL_NAMES).include?(File.basename(entry.path))

        entry.path
      end.first(MAX_DISCOVERY_FILES)
    end

    def authoritative_native(paths)
      root = paths.find { |path| !path.include?("/") }
      root ? [ root ] : select_one_per_root(paths)
    end

    def foreign_candidates(paths)
      manifest_paths = paths.select { |path| %w[railway.toml railway.json app.json].include?(File.basename(path)) }
      select_one_per_root(manifest_paths)
    end

    def select_one_per_root(paths)
      paths.group_by { |path| File.dirname(path) }.values.map do |root_paths|
        root_paths.min_by { |path| MANIFEST_NAMES.index(File.basename(path)) || MANIFEST_NAMES.length }
      end
    end

    def compose_candidates(candidates, commit_sha)
      services = []
      links = []
      warnings = []
      evidence = []
      original_format = nil
      original_content = nil

      candidates.each do |path|
        raw = file_content(path, commit_sha)
        parsed = ManifestParser.parse(raw, filename: File.basename(path))
        original_format ||= parsed.format_detected
        original_content ||= raw
        root = File.dirname(path) == "." ? nil : File.dirname(path)
        names = {}

        parsed.services.each do |service|
          normalized = service.deep_dup
          original_name = normalized[:name]
          normalized[:name] = inferred_name(original_name, root, candidates.length)
          names[original_name] = normalized[:name]
          normalized[:root_directory] ||= root
          normalized[:source_revision] = commit_sha
          # Only apps need a git source — databases are created via Dokku plugins
          unless %w[database cache queue search].include?(normalized[:category])
            normalized[:source] = (normalized[:source] || {}).merge(
              type: "git", repo: "https://github.com/#{@repository}.git", branch: @branch
            )
          end
          services << normalized.deep_stringify_keys
        end

        parsed.links.each do |link|
          links << link.merge(from: names[link[:from]] || link[:from], to: names[link[:to]] || link[:to]).deep_stringify_keys
        end
        warnings.concat(parsed.warnings.map { |warning| "#{path}: #{warning}" })
        evidence << evidence_for(path, parsed.format_detected, parsed.services)
      end

      [ services, links, warnings, evidence, original_format, original_content ]
    end

    def conventional_services(paths, commit_sha)
      roots = paths.group_by { |path| File.dirname(path) }
      services = []
      evidence = []

      roots.each do |root, root_paths|
        root = nil if root == "."
        dockerfile = root_paths.find { |path| File.basename(path) == "Dockerfile" }
        package = root_paths.find { |path| File.basename(path) == "package.json" }
        gemfile = root_paths.find { |path| File.basename(path) == "Gemfile" }
        next unless dockerfile || package || gemfile

        builder = dockerfile ? "dockerfile" : nil
        subtype = "web"
        name = root.present? ? File.basename(root) : @repository.split("/").last
        services << {
          "name" => name.parameterize,
          "category" => "app",
          "subtype" => subtype,
          "builder" => builder,
          "source" => { "type" => "git", "repo" => "https://github.com/#{@repository}.git", "branch" => @branch },
          "root_directory" => root,
          "source_revision" => commit_sha,
          "env" => {}, "domains" => [], "storage" => [],
          "proxy" => { "enabled" => true, "type" => "traefik", "ports" => [ { "host" => 80, "container" => 3000 } ] },
          "checks" => { "enabled" => true }, "scripts" => {}
        }.compact
        evidence << {
          path: dockerfile || package || gemfile,
          format: "convention",
          decision: dockerfile ? "Dockerfile build" : "Automatic runtime build",
          confidence: dockerfile ? "high" : "medium"
        }
      end
      [ services, evidence, nil, nil ]
    end

    def file_content(path, commit_sha)
      content = @client.contents(@repository, path: path, ref: commit_sha)
      Base64.decode64(content.content.to_s).force_encoding("UTF-8")
    end

    def inferred_name(original, root, multiple)
      return original unless original == "app" && (root.present? || multiple > 1)

      (root.present? ? File.basename(root) : @repository.split("/").last).parameterize
    end

    def unique_service_names(services)
      counts = Hash.new(0)
      services.each do |service|
        base = service.fetch("name").presence || "service"
        counts[base] += 1
        service["name"] = "#{base}-#{counts[base]}" if counts[base] > 1
      end
    end

    def evidence_for(path, format, parsed_services)
      {
        path: path,
        format: format,
        decision: parsed_services.length > 1 ? "#{parsed_services.length} services declared" : "Service configuration declared",
        confidence: "high"
      }
    end

    def superseded_manifest_warnings(native, paths)
      return [] if native.empty?

      ignored = paths.select { |path| %w[railway.toml railway.json app.json].include?(File.basename(path)) }
      return [] if ignored.empty?

      [ "RailDock used the native manifest and ignored #{ignored.length} older compatibility manifest#{'s' if ignored.length != 1}." ]
    end
end
