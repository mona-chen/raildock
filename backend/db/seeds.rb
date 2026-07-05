# Rails seeds file
# RailDock does not rely on seed data for core functionality.
# Admin users are created via the /setup web UI.
# Server configuration is handled by install.sh or scripts/setup-dev.sh.
# Projects and services are created by users through the dashboard.
#
# If you need demo data for development, run: make seed
# Or add your own seed data below.

PluginRegistry.seed! if defined?(PluginRegistry)

puts "RailDock: Built-in plugins seeded. Use the setup UI to create your admin account."
