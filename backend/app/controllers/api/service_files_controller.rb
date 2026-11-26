module Api
  class ServiceFilesController < BaseController
    include Authorizable

    before_action :set_service
    before_action :ensure_app

    def index
      authorize_service!(@service, action: :read)
      render json: browser.list(params[:path])
    rescue AppFileBrowser::Error => error
      render_file_error(error)
    end

    def content
      authorize_service!(@service, action: :read)
      render json: browser.preview(params[:path])
    rescue AppFileBrowser::Error => error
      render_file_error(error)
    end

    def download
      authorize_service!(@service, action: :read)
      file = browser.download(params[:path])
      send_data file[:data], filename: file[:filename], type: "application/octet-stream", disposition: "attachment"
    rescue AppFileBrowser::Error => error
      render_file_error(error)
    end

    def create
      authorize_service!(@service, action: :update)

      upload = params[:file]
      unless upload.respond_to?(:tempfile) && upload.respond_to?(:original_filename)
        return render json: { error: "Choose a file to upload", code: "file_required" }, status: :unprocessable_entity
      end

      ServiceOperationLock.with(@service) do
        result = browser.write(
          params[:path],
          upload.original_filename,
          upload.tempfile.path,
          overwrite: ActiveModel::Type::Boolean.new.cast(params[:overwrite]) == true
        )
        ActivityEvent.create!(
          project: @service.project,
          service_name: @service.name,
          action: :updated,
          message: "Uploaded #{result[:name]} to #{result[:path]} in the #{browser.process_type} container"
        )
        render json: result, status: :created
      end
    rescue AppFileBrowser::Error => error
      render_file_error(error)
    end

    private

    def set_service
      @service = Service.find(params[:service_id])
    end

    def ensure_app
      return if @service.service_type_app?

      render json: { error: "File browsing is available for application services", code: "not_an_app" }, status: :unprocessable_entity
    end

    def browser
      @browser ||= AppFileBrowser.new(@service, process_type: params[:process].presence || params[:process_type])
    end

    def render_file_error(error)
      render json: { error: error.message, code: error.code }.compact, status: error.status
    end
  end
end
