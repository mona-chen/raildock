# frozen_string_literal: true

namespace :templates do
  desc "Fix Coolify placeholders → RailDock variables"
  task fix: :environment do
    dir = Rails.root.join("config/templates")
    dry_run = ENV["DRY_RUN"] == "1"
    fixed = 0

    Dir["#{dir}/*.toml"].sort.each do |path|
      content = File.read(path)
      original = content.dup
      name = File.basename(path, ".toml")

      # Collect shared suffixes — credentials shared across services
      users = content.scan(/\$SERVICE_USER_([A-Z0-9_]+)/).flatten
      pass = content.scan(/\$SERVICE_PASSWORD(?:_64)?_([A-Z0-9_]+)/).flatten
      shared = (users + pass).tally.select { |_, c| c > 1 }.keys

      # ── Coolify placeholders ────────────────────────────────
      # For shared suffixes: keep original (will be handled by linked refs later)
      # For unique suffixes: replace with ${{ secret() }}
      content = content.gsub(/\$SERVICE_USER_([A-Z0-9_]+)/) do |m|
        shared.include?($1) ? m : '${{ secret() }}'
      end
      content = content.gsub(/\$SERVICE_PASSWORD(?:_64)?_([A-Z0-9_]+)/) do |m|
        shared.include?($1) ? m : '${{ secret() }}'
      end
      content.gsub!(/\$SERVICE_USER(?!_)/, '${{ secret() }}')
      content.gsub!(/\$SERVICE_PASSWORD(?!_)/, '${{ secret() }}')
      content.gsub!(/\$SERVICE_URL(_[A-Z0-9_]+)?/, 'https://${{ RAILDOCK_PUBLIC_DOMAIN }}')
      content.gsub!(/\$SERVICE_FQDN(_[A-Z0-9_]+)?/, '${{ RAILDOCK_PUBLIC_DOMAIN }}')
      content.gsub!(/\$SERVICE_BASE64(_[A-Z0-9_]+)?/, '${{ secret() }}')
      content.gsub!(%r{"https?://(?:app\.)?example\.com[^"]*"}, '"https://${{ RAILDOCK_PUBLIC_DOMAIN }}"')
      content.gsub!(/\b(MYSQL_USER|POSTGRES_USER)\s*=\s*"user"\b/) { "#{$1} = \"${{ secret() }}\"" }
      content.gsub!(/\bCHANGE_ME\b/, '${{ secret() }}')
      content.gsub!(/\bMINIO_ACCESSKEY\s*=\s*"user"\b/, 'MINIO_ACCESSKEY = "${{ secret() }}"')

      if content != original
        puts "Would fix #{name}" if dry_run
        File.write(path, content) unless dry_run
        fixed += 1
      end
    end

    puts "\nDone: #{fixed}/306 templates updated"
  end
end
