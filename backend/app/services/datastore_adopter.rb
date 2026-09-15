# frozen_string_literal: true

# Records a datastore that already exists on a host as a RailDock Service.
#
# Adoption is deliberately not provisioning: nothing is created, renamed, or
# restarted on the host. The row exists so data that is currently invisible
# shows up in the dashboard, becomes eligible for scheduled backups, and is
# protected from manifest reconciliation — an adopted service is UI-managed,
# and the reconciler never destroys UI-managed services.
class DatastoreAdopter
  class NotAdoptable < StandardError; end

  # Dokku reports other states ("missing", "not deployed"); RailDock's schema
  # accepts this subset, and "stopped" is the honest default for an unknown one.
  RUNNING_STATUS = "running"
  STOPPED_STATUS = "stopped"

  attr_reader :server, :user

  def initialize(server, user: nil, scanner: nil)
    @server = server
    @user = user
    @scanner = scanner
  end

  # Returns the created Service, or raises NotAdoptable with a reason the UI can
  # show verbatim.
  def adopt!(resource_name:, project:, name: nil)
    resource = resource_for!(resource_name, project)

    service = Service.create!(
      project: project,
      name: name.presence || default_name(resource[:name], project),
      service_type: resource[:service_type],
      subtype: resource[:subtype],
      dokku_app_name: resource[:name],
      managed_by: "ui",
      status: adoptable_status(resource[:status]),
      config: adopted_config(resource)
    )

    relink(service, resource, project)
    record_activity(service, resource)
    service
  end

  private
    def scanner
      @scanner ||= UnmanagedDatastoreScanner.new(server)
    end

    # The scanner is the only source of truth for what exists on the host and of
    # what subtype it is: the client sends a name and nothing else.
    def resource_for!(resource_name, project)
      name = resource_name.to_s.strip
      raise NotAdoptable, "Resource name is required" if name.blank?
      raise NotAdoptable, "That project is deployed on a different server" if project.server_id != server.id
      # Checked before the scan result is trusted: a resubmitted form must not be
      # able to record the same Dokku resource twice.
      raise NotAdoptable, "#{name} is already tracked by RailDock" if Service.exists?(dokku_app_name: name)

      result = scanner.scan
      raise NotAdoptable, result[:error].presence || "Could not scan #{server.name}" unless result[:success]

      resource = result[:resources].find { |candidate| candidate[:name] == name }
      return resource if resource

      raise NotAdoptable, "#{name} was not found on #{server.name}"
    end

    def adoptable_status(host_status)
      host_status.to_s == RUNNING_STATUS ? RUNNING_STATUS : STOPPED_STATUS
    end

    # Provenance travels with the service so a later reader can tell an adopted
    # datastore from one RailDock created itself.
    def adopted_config(resource)
      {
        "adopted" => true,
        "adopted_at" => Time.current.utc.iso8601,
        "adopted_by_user_id" => user&.id,
        "host_resource" => resource[:name],
        "host_status" => resource[:status],
        "host_linked_apps" => Array(resource[:linked_apps])
      }.compact
    end

    def default_name(resource_name, project)
      prefix = "#{project.name.to_s.parameterize}-"
      base = resource_name.delete_prefix(prefix).presence || resource_name
      candidate = base
      suffix = 2

      while project.services.exists?(name: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end

      candidate
    end

    # Dokku already injects DATABASE_URL/REDIS_URL into the apps the host reports
    # as linked, so the canvas should show the same wiring. This is bookkeeping
    # only: no Dokku command runs, and env-var sync stays in the deploy path.
    def relink(service, resource, project)
      names = Array(resource[:linked_apps])
      return if names.empty?

      apps = project.services.where(dokku_app_name: names).where.not(id: service.id).to_a
      apps.each do |app|
        ServiceLink.find_or_create_by!(from_service: app, to_service: service)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        Rails.logger.warn "DatastoreAdopter: could not record link #{app.name} -> #{service.name}: #{e.message}"
      end
    end

    def record_activity(service, resource)
      ActivityEvent.create!(
        project: service.project,
        action: "created",
        service_name: service.name,
        message: "Adopted the existing #{resource[:subtype]} datastore #{resource[:name]} from #{server.name}",
        metadata: {
          "adopted" => true,
          "dokku_app_name" => resource[:name],
          "subtype" => resource[:subtype],
          "linked_apps" => Array(resource[:linked_apps])
        }
      )
    rescue => e
      # The datastore is adopted either way; a missing audit row must not undo it.
      Rails.logger.warn "DatastoreAdopter: could not record activity for service #{service.id}: #{e.message}"
    end
end
