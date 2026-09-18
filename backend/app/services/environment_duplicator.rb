# frozen_string_literal: true

# Copies a project's environment — every service and the configuration that
# travels with it — into a brand-new environment.
#
# This is the "Duplicate environment" action Railway and Dokploy both offer, and
# it is deliberately *staged*: nothing is created on the Dokku host, no service
# is deployed, and every copy starts `stopped`. Railway's duplicate flow stages
# each service for review and waits for an explicit deploy, so a mistaken
# duplicate can never quietly publish a second copy of production.
#
# What travels (see `ServiceCopier` for the per-service rules):
#   - build/runtime configuration, environment variables, and storage mounts
#     (each copy gets its own volume name)
#   - backup schedules, remapped to the copied mounts
#   - links between two services that were both copied
#   - process-type scaling rows and the canvas layout
#
# What does not, and why:
#   - domains: two Dokku apps cannot own the same hostname. A copy of a publicly
#     reachable service gets its own temporary domain instead; custom domains are
#     reported in `summary[:warnings]` so the operator can attach them on purpose.
#   - deployments, backups, metrics, PITR: history, not configuration.
class EnvironmentDuplicator
  Result = Struct.new(:environment, :services, :summary, keyword_init: true)

  def initialize(source, name:, description: nil)
    @source = source
    @name = name.to_s.strip
    @description = description
  end

  def call
    if @name.blank?
      return Result.new(
        environment: nil, services: [],
        summary: blank_summary.merge(warnings: [ "An environment name is required." ])
      )
    end

    summary = blank_summary
    environment = nil
    copies = {}

    Service.transaction do
      environment = @source.project.environments.create!(name: @name, description: @description)

      ordered_services.each do |source_service|
        copies[source_service.id] = ServiceCopier.new(source_service, environment, summary: summary).call
      end

      summary[:links] = ServiceCopier.link_copies!(copies)
      summary[:domains_skipped] = uncopied_domain_count
      summary[:warnings] = [
        domain_warning(summary[:domains_skipped]),
        bind_mount_warning(summary[:bind_mounts])
      ].compact

      ActivityEvent.create!(
        project: environment.project,
        service_name: environment.name,
        action: :created,
        message: "Duplicated #{@source.name} into #{environment.name} " \
                 "(#{summary[:services]} service#{summary[:services] == 1 ? '' : 's'} staged, not deployed)"
      )
    end

    Result.new(environment: environment, services: copies.values, summary: summary)
  end

  private
    def ordered_services
      @source.services.includes(
        :environment_variables, :storage_mounts, :domains,
        backup_schedules: :storage_mount, outgoing_links: :to_service
      ).order(:canvas_x, :canvas_y, :id)
    end

    # Custom (`temporary: false`) domains on the *source* services. They are the
    # ones deliberately left behind: a temporary domain is regenerated for the
    # copy off its own app name, but a custom one cannot be shared.
    def uncopied_domain_count
      Domain.where(service_id: @source.services.select(:id), temporary: false).count
    end

    def domain_warning(count)
      return nil if count.zero?

      "#{count} custom domain#{count == 1 ? '' : 's'} #{count == 1 ? 'was' : 'were'} not copied — two " \
        "services cannot answer on the same hostname. Attach a domain to the copy when you are ready to " \
        "send it traffic."
    end

    def bind_mount_warning(count)
      return nil if count.zero?

      "#{count} bind mount#{count == 1 ? '' : 's'} point at the same host path as #{@source.name}. " \
        "Every copy shares that directory."
    end

    def blank_summary
      {
        services: 0, variables: 0, volumes: 0, bind_mounts: 0, schedules: 0, links: 0,
        process_types: 0, temporary_domains: 0, domains_skipped: 0,
        warnings: []
      }
    end
end
