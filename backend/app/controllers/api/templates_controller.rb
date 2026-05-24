module Api
  class TemplatesController < BaseController
    include Authorizable

    def index
      templates = TemplateLoader.all.map(&:to_h)
      render json: templates
    end

    def deploy
      template = TemplateLoader.find(params[:id])
      return render json: { error: 'Template not found' }, status: :not_found unless template

      project = scoped_projects.find_by(id: params[:project_id])
      return render json: { error: 'Project not found' }, status: :not_found unless project

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

        service = project.services.create!(
          name: svc_def[:name],
          service_type: svc_def[:category],
          subtype: svc_def[:subtype],
          status: svc_def[:category] == "database" ? "running" : "stopped",
          builder: builder,
          git_repo: svc_def.dig(:source, :repo),
          branch: svc_def.dig(:source, :branch),
          docker_image: docker_image,
          version: svc_def[:version],
          start_command: svc_def[:start_command],
          exposed: svc_def[:exposed],
          port: svc_def[:port],
          config: build_config(svc_def),
          managed_by: "manifest"
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
          mount = service.storage_mounts.create!(
            host_path: st[:host],
            container_path: st[:container]
          )

          # Sync to Dokku if server connected
          if project.server&.ssh_key.present?
            engine = DokkuEngine.new(project.server)
            engine.storage_mount(service.dokku_app_name, st[:host], st[:container])
          end
        end

        # Create Dokku resources if server connected
        if project.server&.ssh_key.present?
          engine = DokkuEngine.new(project.server)
          app_name = service.dokku_app_name

          if service.service_type_database?
            case service.subtype
            when "postgres" then engine.postgres_create(app_name)
            when "redis" then engine.redis_create(app_name)
            when "mysql" then engine.mysql_create(app_name)
            when "mongo" then engine.mongo_create(app_name)
            end
          else
            engine.app_create(app_name)
            proxy_type = svc_def.dig(:proxy, :type) || "traefik"
            engine.proxy_set(app_name, proxy_type)
          end
        end

        service
      end

      # Create links
      template.links.each do |link|
        from_svc = project.services.find_by(name: link[:from])
        to_svc = project.services.find_by(name: link[:to])
        next unless from_svc && to_svc

        ServiceLink.create!(from_service: from_svc, to_service: to_svc)

        # Dokku link
        if to_svc.service_type_database? && project.server&.ssh_key.present?
          engine = DokkuEngine.new(project.server)
          begin
            engine.send("#{to_svc.subtype}_link", from_svc.dokku_app_name, to_svc.dokku_app_name)
            # Sync injected env vars
            sync_dokku_env_vars(engine, from_svc)
          rescue => e
            Rails.logger.error "Dokku link failed for #{link[:from]} -> #{link[:to]}: #{e.message}"
          end
        end
      end

      render json: {
        created: created.map { |s| { id: s.id, name: s.name, type: s.service_type, subtype: s.subtype } }
      }
    end

    private

    def build_config(svc_def)
      config = {}
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

    def sync_dokku_env_vars(engine, service)
      result = engine.config_show(service.dokku_app_name)
      return unless result[:success]

      result[:output].each_line do |line|
        next unless line.include?(":")
        key, value = line.split(":", 2)
        next unless key && value
        key = key.strip
        value = value.strip
        next unless key.match?(/^(DATABASE_URL|REDIS_URL|MONGO_URL|MYSQL_URL|DATABASE_PRIVATE_URL|REDIS_PRIVATE_URL)/i)

        service.environment_variables.find_or_initialize_by(key: key).tap do |ev|
          ev.value = value
          ev.is_dokku_internal = true
          ev.source = "dokku-link"
          ev.save!
        end
      end
    rescue => e
      Rails.logger.error "Failed to sync Dokku env vars for #{service.dokku_app_name}: #{e.message}"
    end
  end
end
