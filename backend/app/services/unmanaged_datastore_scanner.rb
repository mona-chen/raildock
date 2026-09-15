# frozen_string_literal: true

require "shellwords"

# Lists datastores that live on a server but have no Service record in RailDock.
#
# A datastore can outlive its RailDock record — a reconcile that dropped the row,
# or one created by hand with `dokku postgres:create`. Once that happens the data
# is invisible: no dashboard entry, no schedule, no backup, and nothing warning
# anyone that this volume holds the only copy. This scanner is the read-only half
# of recovering it; DatastoreAdopter is the other half.
#
# Only plugins Dokku already has installed are queried. Invoking `dokku mysql:list`
# on a host without the mysql plugin makes Dokku *install* it, so the installed
# plugin list is always read first.
class UnmanagedDatastoreScanner
  # Dokku resource names are constrained; refusing anything else keeps a scanned
  # name out of the shell command that inspects it.
  RESOURCE_NAME = /\A[a-z0-9][a-z0-9._-]*\z/
  STATUS_LINE = /^\s*Status:\s+(\S+)/
  ERRORS_KEPT = 5

  attr_reader :server

  def initialize(server, engine: nil)
    @server = server
    @engine = engine
  end

  # Returns { success:, resources: [...], errors: [...] }.
  # A resource is { name:, subtype:, service_type:, status:, linked_apps: [] }.
  def scan
    plugins = installed_plugins
    return { success: false, error: "Could not read the Dokku plugin list", resources: [], errors: [] } if plugins.nil?

    discovered = []
    errors = []
    seen = Set.new

    datastore_subtypes(plugins).each do |subtype|
      result = engine.run(subtype.dokku_command(:list))

      unless result[:success]
        errors << "#{subtype.dokku_command(:list)} failed: #{result[:output].to_s.strip.truncate(200)}"
        next
      end

      parse_names(result[:output]).each do |name|
        next unless name.match?(RESOURCE_NAME)
        next unless seen.add?(name)

        discovered << { name: name, subtype: subtype.subtype, service_type: subtype.service_type }
      end
    end

    resources = discovered.reject { |resource| tracked_names.include?(resource[:name]) }
    resources.each do |resource|
      resource[:status] = status_for(resource)
      resource[:linked_apps] = linked_apps_for(resource)
    end

    { success: true, resources: resources, errors: errors.first(ERRORS_KEPT) }
  rescue => e
    Rails.logger.error "UnmanagedDatastoreScanner failed for server #{server.id}: #{e.message}"
    { success: false, error: e.message, resources: [], errors: [] }
  end

  private
    def engine
      @engine ||= DokkuEngine.new(server)
    end

    # nil means "the host did not answer"; [] means "answered, nothing installed".
    def installed_plugins
      result = engine.run("plugin:list")
      return nil unless result[:success]

      result[:output].to_s.each_line.filter_map do |line|
        name, _version, status = line.split
        next if name.blank? || !name.match?(RESOURCE_NAME)
        # Only "enabled" rows are real, invocable plugins: `plugin:list` also
        # reports disabled ones, and a header line ("=====> Installed Plugins")
        # splits into a name that the resource-name check already rejects.
        next unless status == "enabled"

        name
      end
    end

    # One Dokku plugin can back several RailDock subtypes (the mysql plugin also
    # serves mariadb), so each plugin is listed once and its names are attributed
    # to the subtype that matches the namespace.
    def datastore_subtypes(plugins)
      ServiceSubtype.where.not(dokku_plugin: nil).where(dokku_plugin: plugins).order(:subtype)
        .group_by { |subtype| subtype.command_namespace.presence || subtype.dokku_plugin }
        .map { |namespace, subtypes| subtypes.find { |subtype| subtype.subtype == namespace } || subtypes.first }
    end

    def parse_names(output)
      output.to_s.each_line.filter_map do |line|
        value = line.strip
        next if value.blank? || value.start_with?("=====>")

        value
      end
    end

    # Every resource RailDock already knows about, on any server: a name claimed
    # elsewhere must not be offered for adoption twice.
    def tracked_names
      @tracked_names ||= Service.where.not(dokku_app_name: nil).pluck(:dokku_app_name).to_set
    end

    def status_for(resource)
      subtype = ServiceSubtype.find_by(subtype: resource[:subtype])
      return "unknown" if subtype.blank?

      result = engine.run("#{subtype.dokku_command(:info)} #{Shellwords.escape(resource[:name])}")
      return "unknown" unless result[:success]

      match = result[:output].to_s.match(STATUS_LINE)
      match ? match[1] : "unknown"
    end

    def linked_apps_for(resource)
      subtype = ServiceSubtype.find_by(subtype: resource[:subtype])
      return [] if subtype.blank?

      result = engine.run("#{subtype.dokku_command(:links)} #{Shellwords.escape(resource[:name])}")
      return [] unless result[:success]

      parse_names(result[:output])
    end
end
