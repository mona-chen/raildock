module Api
  # Only named, capability-checked Dokku operations. Never accepts shell commands.
  class NativeServicesController < BaseController
    include Authorizable
    before_action :find_service

    def show
      engine = DokkuEngine.new(@service.project.server)
      capabilities = DokkuCapabilities.new(engine).read
      data = { capabilities: capabilities }
      %w[builds cron resource].each do |name|
        next unless capabilities[:features][name]
        command = { "builds" => "builds:list", "cron" => "cron:list", "resource" => "resource:report" }.fetch(name)
        result = engine.run("#{command} #{engine.escape(@service.dokku_app_name)} --format json")
        data[name] = result[:success] ? JSON.parse(result[:output]) : { error: "Could not read #{name} from the host" }
      rescue JSON::ParserError
        data[name] = { error: "Host returned an unsupported #{name} report" }
      end
      render json: data
    rescue ServiceSettingsSync::ApplyError => e
      render json: { error: e.message }, status: :bad_gateway
    end

    def create
      authorize_service!(@service, action: :update)
      ServiceOperationLock.with(@service) do
        engine = DokkuEngine.new(@service.project.server)
        feature = params[:operation].to_s.split("_").first
        capabilities = DokkuCapabilities.new(engine).read
        unless capabilities[:features][feature]
          return render json: { error: "This host does not support #{feature}", code: "unsupported_capability" }, status: :unprocessable_entity
        end
        app = @service.dokku_app_name
        result = case params[:operation]
        when "cron_run", "cron_suspend", "cron_resume"
          jobs = engine.cron_list(app)
          raise ServiceSettingsSync::ApplyError, "Could not verify the scheduled task" unless jobs[:success]
          id = params[:task_id].to_s
          raise ArgumentError, "Task no longer exists; refresh the schedule" unless JSON.parse(jobs[:output]).any? { |job| job["id"] == id }
          engine.public_send(params[:operation], app, id)
        when "registry_login"
          registry = registry_host!
          username = params.require(:username).to_s
          password = params.require(:password).to_s
          raise ArgumentError, "Username and password are required" if username.blank? || password.blank?
          engine.run_with_stdin("registry:login #{engine.escape(app)} --password-stdin #{engine.escape(registry)} #{engine.escape(username)}", "#{password}\n")
        when "registry_logout"
          engine.run("registry:logout #{engine.escape(app)} #{engine.escape(registry_host!)}")
        when "logs_rotation"
          size = Integer(params[:size_mb])
          raise ArgumentError, "Use a log size between 1 and 100 MB" unless (1..100).cover?(size)
          result = engine.run("logs:set #{engine.escape(app)} max-size #{size}m")
          result
        else
          raise ArgumentError, "Unsupported operation"
        end
        # Registry errors may contain credentials from an upstream server. Return
        # a stable actionable error, never raw output from authentication commands.
        raise ServiceSettingsSync::ApplyError, "Dokku could not complete this operation. Check host access and configuration." unless result[:success]
        ActivityEvent.create!(project: @service.project, service_name: @service.name, action: :updated, message: "Native Dokku operation: #{params[:operation]}")
        render json: { success: true, requires_deploy: params[:operation] == "logs_rotation" }
      end
    rescue ArgumentError, ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue ServiceSettingsSync::ApplyError => e
      render json: { error: e.message }, status: :bad_gateway
    end

    private

    def find_service
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end

    def registry_host!
      value = params.require(:registry).to_s
      raise ArgumentError, "Enter a registry hostname, such as ghcr.io" unless value.match?(/\A[a-zA-Z0-9][a-zA-Z0-9.-]*(?::[0-9]{1,5})?\z/)
      value
    end
  end
end
