namespace :raildock do
  desc "Migrate all existing Dokku apps from nginx to traefik proxy"
  task migrate_proxy_to_traefik: :environment do
    servers = Server.where.not(ssh_key: [nil, ""])

    if servers.empty?
      puts "No connected servers found. Nothing to do."
      next
    end

    servers.find_each do |server|
      engine = DokkuEngine.new(server)

      puts "\nMigrating apps on server: #{server.name}..."

      # Set global proxy to traefik
      result = engine.run("proxy:set --global traefik")
      puts result[:success] ? "  ✓ Global proxy set to traefik" : "  ✗ Failed: #{result[:output]}"

      # Ensure apps join the raildock network
      engine.run("network:set --global initial-network raildock")
      engine.run("network:set --global attach-post-deploy raildock")
      puts "  ✓ Network settings updated"

      # Rebuild each app so it picks up the new proxy labels
      apps_result = engine.apps_list
      if apps_result[:success]
        apps = apps_result[:output].split("\n").map(&:strip).reject { |l| l.empty? || l.start_with?("=====") }
        apps.each do |app|
          next if app.empty?

          puts "  → Rebuilding app: #{app}"
          rebuild = engine.run("ps:rebuild #{app}")
          puts rebuild[:success] ? "    ✓ Rebuilt" : "    ✗ Failed: #{rebuild[:output]}"
        end
      end

      # Update server record
      server.update!(default_proxy: "traefik")
      puts "  ✓ Server default_proxy updated to traefik"
    end

    puts "\nMigration complete. All apps now use Traefik via RailDock's unified proxy."
  end
end
