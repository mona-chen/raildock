#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates RailDock templates from a local Coolify repo clone.
# Much faster than import_coolify_templates.rb since it doesn't hit the network.

require "fileutils"
require_relative "../app/services/compose_to_manifest"

COOLIFY_DIR = "/tmp/coolify-templates"
COMPOSE_DIR = File.join(COOLIFY_DIR, "templates", "compose")
LOGOS_DIR = File.join(COOLIFY_DIR, "public", "svgs")

RAILDOCK_TEMPLATES_DIR = File.expand_path("../config/templates", __dir__)
RAILDOCK_LOGOS_DIR = File.expand_path("../public/templates/logos", __dir__)

SKIP_LIST = %w[
  supabase appwrite affine authentik jitsi gitlab
  nextcloud-with-mariadb nextcloud-with-mysql nextcloud-with-postgres
  penpot penpot-with-s3 signoz posthog
  unleash-with-postgresql unleash-without-database
  matrix-synapse-with-postgresql matrix-synapse-with-sqlite
  elasticsearch-with-kibana minio-community-edition
  ente-photos-with-s3 ente-photos
  forgejo-with-runner forgejo-with-runner-with-mariadb
  forgejo-with-runner-with-mysql forgejo-with-runner-with-postgresql
  gitea-runner gitea-with-mariadb gitea-with-mysql gitea-with-postgresql
  ghost n8n-with-postgres-and-worker n8n-with-postgresql
  flowise-with-databases freshrss-with-mariadb freshrss-with-mysql freshrss-with-postgresql
  wordpress-with-mariadb wordpress-with-mysql wordpress-without-database
  directus-with-postgresql docuseal-with-postgres pocket-id-with-postgresql
  vikunja-with-postgresql yamtrack-with-postgresql
  calibre-web-automated-book-downloader pingvinshare-with-clamav
  uptime-kuma-with-mariadb uptime-kuma-with-mysql plausible gotify
].freeze

def ensure_dirs
  FileUtils.mkdir_p(RAILDOCK_TEMPLATES_DIR)
  FileUtils.mkdir_p(RAILDOCK_LOGOS_DIR)
end

def process_template(yaml_path)
  slug = File.basename(yaml_path, File.extname(yaml_path))

  if SKIP_LIST.include?(slug)
    puts "  ⏭️  Skipping #{slug}"
    return { status: :skipped }
  end

  yaml_content = File.read(yaml_path)
  metadata = ComposeToManifest.extract_coolify_metadata(yaml_content)

  converter = ComposeToManifest.new(yaml_content, metadata)
  result = converter.convert(slug: slug)

  unless result
    puts "  ❌ #{slug}: conversion failed"
    return { status: :error }
  end

  # Add logo
  logo_path = metadata["logo"]
  toml_content = result.toml
  if logo_path
    lines = toml_content.lines
    category_idx = lines.find_index { |l| l.start_with?("category =") }
    if category_idx
      lines.insert(category_idx + 1, "logo = \"#{logo_path}\"\n")
      toml_content = lines.join
    end
  end

  File.write(File.join(RAILDOCK_TEMPLATES_DIR, "#{slug}.toml"), toml_content)

  # Copy logo if exists
  if logo_path
    logo_filename = File.basename(logo_path)
    src = File.join(LOGOS_DIR, logo_filename)
    if File.exist?(src)
      ext = File.extname(logo_filename).downcase
      dest = File.join(RAILDOCK_LOGOS_DIR, "#{slug}#{ext}")
      FileUtils.cp(src, dest) unless File.exist?(dest)
    end
  end

  if result.warnings.any?
    puts "  ⚠️  #{slug}: #{result.warnings.length} warning(s)"
  else
    puts "  ✅ #{slug}"
  end

  { status: :success }
end

def main
  puts "🚀 Regenerating templates from local Coolify clone..."
  ensure_dirs

  files = Dir.glob(File.join(COMPOSE_DIR, "*.{yaml,yml}")).sort
  puts "📦 Found #{files.length} templates"
  puts

  stats = { success: 0, error: 0, skipped: 0 }

  files.each do |path|
    result = process_template(path)
    stats[result[:status]] += 1
  end

  puts
  puts "📊 Results: ✅ #{stats[:success]}  ⏭️ #{stats[:skipped]}  ❌ #{stats[:error]}"
end

main
