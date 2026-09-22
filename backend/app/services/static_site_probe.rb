# frozen_string_literal: true

require "json"

# Reads a repository revision through a connected GitHub App and reports the
# static-site settings it implies: framework, publish directory, Node version.
#
# RepositoryDiscovery probes a repo an operator is about to import; a deploy
# probes the repo it is about to build. Both defer to StaticSiteDetector, so a
# repo Railpack would serve as a static site is configured the same way here.
#
# Deploys cannot skip this. Dokku's railpack and nixpacks build stages reset the
# image ENTRYPOINT, which clears the CMD carrying the builder's start command,
# and a static site has no other process to run: without the publish directory
# RailDock has nothing to put in Dokku's `dockerfile-start-cmd` and the container
# dies with "no command specified" (see StaticSiteConfigurator). Repos RailDock
# cannot read are handled by the deploy failure path instead
# (DeploymentJob#recover_missing_process_command).
class StaticSiteProbe
  # A Dockerfile or a Procfile means the repo already declares how the app is
  # built and started, so RailDock must not attach a static site to it.
  DECLARATIVE_NAMES = %w[Dockerfile Procfile].freeze

  # Everything the probe needs from one directory: what the repo declares about
  # its processes, its package manifest, the framework config files that can
  # move the publish directory, and the bare marker that makes a no-build repo
  # a plain static site.
  RELEVANT_NAMES = (%w[package.json index.html] + DECLARATIVE_NAMES + StaticSiteDetector::CONFIG_FILES).freeze

  def initialize(client:, repository:, ref:)
    @client = client
    @repository = repository
    @ref = ref
  end

  # Returns a StaticSiteDetector::Result, or nil when the repo is not a static
  # frontend, serves itself (Dockerfile/Procfile), or cannot be read.
  def detect(root_directory: nil)
    root = normalize_root(root_directory)
    paths = repository_paths(root)
    return nil if paths.any? { |path| DECLARATIVE_NAMES.include?(File.basename(path)) }

    package_path = paths.find { |path| File.basename(path) == "package.json" }
    if package_path.present?
      package_json = parse_json(file_content(package_path))
      return nil unless package_json

      return StaticSiteDetector.detect(package_json: package_json, files: framework_config_files(paths))
    end

    # No package manifest: the only way this is a static site is as a plain,
    # no-build bundle the Staticfile providers serve directly.
    return StaticSiteDetector.detect_plain_static(index_html: true) if paths.any? { |path| File.basename(path) == "index.html" }

    nil
  rescue Octokit::Error => e
    Rails.logger.warn "StaticSiteProbe: could not read #{@repository}@#{@ref}: #{e.message}"
    nil
  end

  private

  def normalize_root(root_directory)
    root = root_directory.to_s.strip
    root.empty? || root == "." ? nil : root
  end

  # Paths of the relevant blobs that sit directly in the service's root.
  def repository_paths(root)
    tree = @client.tree(@repository, @ref, recursive: true)
    if tree.truncated
      Rails.logger.warn "StaticSiteProbe: #{@repository}@#{@ref} tree is truncated, skipping detection"
      return []
    end

    tree.tree.filter_map do |entry|
      next unless entry.type == "blob"
      next unless File.dirname(entry.path) == (root || ".")
      next unless RELEVANT_NAMES.include?(File.basename(entry.path))

      entry.path
    end
  rescue Octokit::NotFound
    []
  end

  def framework_config_files(paths)
    paths.select { |path| StaticSiteDetector::CONFIG_FILES.include?(File.basename(path)) }
         .to_h { |path| [ File.basename(path), file_content(path) ] }
  end

  def file_content(path)
    content = @client.contents(@repository, path: path, ref: @ref)
    Base64.decode64(content.content.to_s).force_encoding("UTF-8")
  rescue Octokit::NotFound
    ""
  end

  def parse_json(content)
    JSON.parse(content.to_s)
  rescue JSON::ParserError
    Rails.logger.warn "StaticSiteProbe: ignoring invalid package.json in #{@repository}@#{@ref}"
    nil
  end
end
