require "shellwords"

module Api
  class TemplatesController < BaseController
    include Authorizable

    def index
      templates = TemplateLoader.all.map(&:to_h)
      render json: templates
    end

    def deploy
      template = TemplateLoader.find(params[:id])
      return render json: { error: "Template not found" }, status: :not_found unless template

      project = scoped_projects.find_by(id: params[:project_id])
      return render json: { error: "Project not found" }, status: :not_found unless project

      created, deployments = deploy_template_services(template, project)

      if project.server&.ssh_key.present?
        TemplateDeployJob.perform_later(
          project.id,
          template.id,
          created.map(&:id),
          deployments.index_by { |d| d.service_id.to_s }.transform_values(&:id)
        )
      end

      render json: {
        created: created.map { |s| { id: s.id, name: s.name, type: s.service_type, subtype: s.subtype, status: s.status } }
      }
    end

    private

    def deploy_template_services(template, project)
      created = template.services.map do |svc_def|
        is_app = svc_def[:category] == "app"

        # Determine builder
        builder = svc_def[:builder]
        builder ||= is_app ? "nixpacks" : nil

        # Determine docker image for one-click services
        docker_image = svc_def[:docker_image]
        if docker_image.blank? && svc_def[:source].nil? && !is_app
          docker_image = Service::DEFAULT_DOCKER_IMAGES[svc_def[:subtype]]
        end

        initial_status = if svc_def[:category] == "database"
          "running"
        elsif project.server&.ssh_key.present?
          "deploying"
        else
          "stopped"
        end

        service = project.services.create!(
          name: svc_def[:name],
          service_type: svc_def[:category],
          subtype: svc_def[:subtype],
          status: initial_status,
          builder: builder,
          git_repo: svc_def.dig(:source, :repo),
          branch: svc_def.dig(:source, :branch),
          docker_image: docker_image,
          version: svc_def[:version],
          start_command: svc_def[:start_command],
          exposed: svc_def[:exposed],
          port: svc_def[:port],
          config: build_config(svc_def),
          managed_by: "ui"
        )

        # Create process types from scaling
        (svc_def[:scaling] || {}).each do |pt_name, qty|
          service.process_types.create!(name: pt_name, quantity: qty, running: 0, command: "")
        end

        # Create env vars (skip empty values — belt and suspenders)
        (svc_def[:env] || {}).each do |key, value|
          next if value.to_s.blank?
          service.environment_variables.create!(key: key, value: value)
        end

        # Create storage mounts
        (svc_def[:storage] || []).each do |st|
          next if st[:host].blank? || st[:container].blank?
          service.storage_mounts.create!(
            host_path: st[:host],
            container_path: st[:container]
          )
        end

        service
      end

      # Create pending Deployment records for app services immediately so the
      # user sees "deploying" state and a pending deployment instead of "stopped"
      # with no indicator. TemplateDeployJob#enqueue_app_deployments will pick
      # these up and enqueue the actual DeploymentJob.
      deployments = []
      if project.server&.ssh_key.present?
        app_services = created.select(&:service_type_app?)
        app_services.each do |svc|
          deployments << svc.deployments.create!(
            status: :pending,
            started_at: Time.current,
            branch: svc.branch || "main"
          )
        end
      end

      # Create DB-only service links so the background job can resolve them
      created_by_name = created.index_by(&:name)
      template.links.each do |link|
        from_svc = created_by_name[link[:from]]
        to_svc = created_by_name[link[:to]]
        next unless from_svc && to_svc

        ServiceLink.find_or_create_by!(from_service: from_svc, to_service: to_svc)
      end

      [ created, deployments ]
    end

    def build_config(svc_def)
      config = {}
      config["depends_on"] = svc_def[:depends_on] if svc_def[:depends_on].present?
      config["proxy"] = svc_def[:proxy] if svc_def[:proxy]
      config["checks"] = svc_def[:checks] if svc_def[:checks]
      config["cron"] = svc_def[:cron] if svc_def[:cron]
      config["dockerOptions"] = svc_def[:docker_options] if svc_def[:docker_options]
      config["resourceLimits"] = svc_def[:limits] if svc_def[:limits]
      config["resourceReservations"] = svc_def[:reservations] if svc_def[:reservations]
      config["traefik"] = svc_def[:traefik_labels] if svc_def[:traefik_labels]
      config["letsencrypt"] = svc_def[:letsencrypt] if svc_def[:letsencrypt]
      config
    end
  end
end
