#!/usr/bin/env ruby
# frozen_string_literal: true

# Imports Coolify one-click service templates into RailDock's template directory.
#
# Usage:
#   cd backend
#   bundle exec ruby scripts/import_coolify_templates.rb
#
# This script:
# 1. Fetches the list of compose templates from github.com/coollabsio/coolify (v4.x branch)
# 2. Converts each Docker Compose YAML to RailDock TOML via ComposeToManifest
# 3. Downloads SVG logos
# 4. Writes templates to config/templates/ and logos to public/templates/logos/
# 5. Skips templates that can't be converted (complex stacks, parse errors)
#
# Run it after updating the converter logic to regenerate all templates.

require "net/http"
require "json"
require "fileutils"
require_relative "../app/services/compose_to_manifest"

COOLIFY_REPO = "coollabsio/coolify"
COOLIFY_BRANCH = "v4.x"
COMPOSE_DIR = "templates/compose"
LOGOS_DIR = "public/svgs"

RAILDOCK_TEMPLATES_DIR = File.expand_path("../config/templates", __dir__)
RAILDOCK_LOGOS_DIR = File.expand_path("../public/templates/logos", __dir__)

# GitHub raw content base URL
RAW_BASE = "https://raw.githubusercontent.com/#{COOLIFY_REPO}/#{COOLIFY_BRANCH}"
API_BASE = "https://api.github.com/repos/#{COOLIFY_REPO}/contents"

# Templates that are too complex to auto-convert (skip these)
SKIP_LIST = %w[
  supabase
  appwrite
  affine
  authentik
  jitsi
  gitlab
  nextcloud-with-mariadb
  nextcloud-with-mysql
  nextcloud-with-postgres
  penpot
  penpot-with-s3
  signoz
  posthog
  unleash-with-postgresql
  unleash-without-database
  matrix-synapse-with-postgresql
  matrix-synapse-with-sqlite
  elasticsearch-with-kibana
  minio-community-edition
  ente-photos-with-s3
  ente-photos
  forgejo-with-runner
  forgejo-with-runner-with-mariadb
  forgejo-with-runner-with-mysql
  forgejo-with-runner-with-postgresql
  gitea-runner
  gitea-with-mariadb
  gitea-with-mysql
  gitea-with-postgresql
  ghost
  n8n-with-postgres-and-worker
  n8n-with-postgresql
  flowise-with-databases
  freshrss-with-mariadb
  freshrss-with-mysql
  freshrss-with-postgresql
  wordpress-with-mariadb
  wordpress-with-mysql
  wordpress-without-database
  directus-with-postgresql
  docuseal-with-postgres
  pocket-id-with-postgresql
  vikunja-with-postgresql
  yamtrack-with-postgresql
  calibre-web-automated-book-downloader
  pingvinshare-with-clamav
  uptime-kuma-with-mariadb
  uptime-kuma-with-mysql
  plausible
  gotify
  lobechat
].freeze

def github_api(path)
  uri = URI("#{API_BASE}/#{path}?ref=#{COOLIFY_BRANCH}")
  req = Net::HTTP::Get.new(uri)
  req["Accept"] = "application/vnd.github.v3+json"
  req["User-Agent"] = "RailDock-Template-Importer"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

  if res.code == "403" && res.body.include?("rate limit")
    puts "⚠️  GitHub API rate limit hit. Try again later or use a token."
    exit 1
  end

  JSON.parse(res.body)
rescue => e
  puts "⚠️  API error for #{path}: #{e.message}"
  nil
end

def fetch_raw(path)
  uri = URI("#{RAW_BASE}/#{path}")
  res = Net::HTTP.get_response(uri)
  return nil unless res.is_a?(Net::HTTPSuccess)
  res.body
rescue => e
  puts "⚠️  Failed to fetch #{path}: #{e.message}"
  nil
end

def slugify(name)
  name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
end

def ensure_dirs
  FileUtils.mkdir_p(RAILDOCK_TEMPLATES_DIR)
  FileUtils.mkdir_p(RAILDOCK_LOGOS_DIR)
end

def process_template(file_info)
  filename = file_info["name"]
  slug = File.basename(filename, File.extname(filename))

  if SKIP_LIST.include?(slug)
    puts "  ⏭️  Skipping #{slug} (complex multi-service stack)"
    return { status: :skipped, slug: slug }
  end

  # Fetch compose YAML
  yaml_content = fetch_raw("#{COMPOSE_DIR}/#{filename}")
  unless yaml_content
    puts "  ❌ Failed to fetch #{filename}"
    return { status: :error, slug: slug, reason: "fetch failed" }
  end

  # Extract metadata from comments
  metadata = ComposeToManifest.extract_coolify_metadata(yaml_content)

  # Convert
  converter = ComposeToManifest.new(yaml_content, metadata)
  result = converter.convert

  unless result
    puts "  ❌ #{slug}: conversion failed"
    return { status: :error, slug: slug, reason: "conversion failed" }
  end

  # Add logo reference to manifest TOML if available
  logo_path = metadata["logo"]
  toml_content = result.toml

  if logo_path
    # Insert logo after category line
    lines = toml_content.lines
    category_idx = lines.find_index { |l| l.start_with?("category =") }
    if category_idx
      lines.insert(category_idx + 1, "logo = \"#{logo_path}\"\n")
      toml_content = lines.join
    end
  end

  # Write TOML
  toml_path = File.join(RAILDOCK_TEMPLATES_DIR, "#{slug}.toml")
  File.write(toml_path, toml_content)

  # Download logo
  logo_result = download_logo(logo_path, slug)

  if result.warnings.any?
    puts "  ⚠️  #{slug}: #{result.warnings.length} warning(s)"
    result.warnings.each { |w| puts "      • #{w}" }
  else
    puts "  ✅ #{slug}"
  end

  { status: :success, slug: slug, warnings: result.warnings.length, logo: logo_result }
end

def download_logo(logo_path, slug)
  return nil unless logo_path

  # Coolify logos are in public/svgs/*.svg
  logo_filename = File.basename(logo_path)
  ext = File.extname(logo_filename).downcase
  return nil unless %w[.svg .png .jpg .jpeg .webp].include?(ext)

  raw_logo = fetch_raw("#{LOGOS_DIR}/#{logo_filename}")
  unless raw_logo
    puts "      ⚠️  Logo not found: #{logo_path}"
    return nil
  end

  dest = File.join(RAILDOCK_LOGOS_DIR, "#{slug}#{ext}")
  File.write(dest, raw_logo)
  dest
end

def main
  puts "🚀 Importing Coolify templates..."
  puts "   Source: #{COOLIFY_REPO} (#{COOLIFY_BRANCH})"
  puts "   Destination: #{RAILDOCK_TEMPLATES_DIR}"
  puts

  ensure_dirs

  # Fetch template list
  files = github_api(COMPOSE_DIR)
  unless files.is_a?(Array)
    puts "❌ Failed to fetch template list from GitHub"
    exit 1
  end

  compose_files = files.select do |f|
    f.is_a?(Hash) && f["type"] == "file" &&
      (f["name"].end_with?(".yaml") || f["name"].end_with?(".yml"))
  end

  puts "📦 Found #{compose_files.length} templates"
  puts

  stats = { success: 0, error: 0, skipped: 0, warnings: 0 }

  compose_files.each do |file_info|
    result = process_template(file_info)
    stats[result[:status]] += 1
    stats[:warnings] += result[:warnings] || 0
  end

  puts
  puts "📊 Results:"
  puts "   ✅ Successfully imported: #{stats[:success]}"
  puts "   ⏭️  Skipped (complex):    #{stats[:skipped]}"
  puts "   ❌ Errors:               #{stats[:error]}"
  puts "   ⚠️  Total warnings:      #{stats[:warnings]}"
  puts
  puts "🎉 Done! Restart the backend to load new templates."
end

main
