module Api
  class ManifestsController < BaseController
    include Authorizable

    before_action :set_and_authorize_project!

    # GET /api/projects/:project_id/manifest
    def show
      content = @project.manifest_content || ManifestGenerator.new(@project).generate(format: :toml)
      render json: {
        content: content,
        format: @project.manifest_format || "raildock.toml",
        drift_detected: @project.manifest_drift_detected,
        last_synced_at: @project.manifest_last_synced_at,
        last_applied_at: @project.manifest_last_applied_at,
        synced: @project.manifest_synced?
      }
    end

    # PATCH /api/projects/:project_id/manifest
    def update
      content = manifest_params[:content]
      format = manifest_params[:format] || detect_format(content)

      # Validate
      begin
        desired = ManifestParser.parse(content, filename: format)
      rescue ManifestParser::ParseError => e
        return render json: { error: "Parse error", details: e.message }, status: :unprocessable_entity
      end

      parsed = JSON.parse(content) rescue TomlRB.parse(content)
      validation = ManifestSchema.validate(parsed)
      unless validation.success?
        return render json: { error: "Validation failed", details: validation.errors }, status: :unprocessable_entity
      end

      # Store manifest
      @project.update!(
        manifest_content: content,
        manifest_format: format,
        manifest_last_synced_at: Time.current,
        manifest_drift_detected: false
      )

      # Auto-preview
      reconciler = ManifestReconciler.new(@project, desired)
      changes = reconciler.diff

      render json: {
        content: content,
        format: format,
        preview: changes.map(&:to_h),
        severity: ChangeClassifier.aggregate(changes),
        warnings: desired.warnings,
        synced: @project.manifest_synced?
      }
    end

    # POST /api/projects/:project_id/manifest/preview
    def preview
      content = @project.manifest_content
      return render json: { error: "No manifest configured" }, status: :not_found unless content.present?

      begin
        desired = ManifestParser.parse(content, filename: @project.manifest_format)
      rescue ManifestParser::ParseError => e
        return render json: { error: "Parse error", details: e.message }, status: :unprocessable_entity
      end

      reconciler = ManifestReconciler.new(@project, desired)
      changes = reconciler.diff

      render json: {
        changes: changes.map(&:to_h),
        severity: ChangeClassifier.aggregate(changes),
        total_changes: changes.length,
        by_severity: ChangeClassifier.group_by_severity(changes).transform_values(&:count),
        warnings: desired.warnings
      }
    end

    # POST /api/projects/:project_id/manifest/apply
    def apply
      content = @project.manifest_content
      return render json: { error: "No manifest configured" }, status: :not_found unless content.present?

      begin
        desired = ManifestParser.parse(content, filename: @project.manifest_format)
      rescue ManifestParser::ParseError => e
        return render json: { error: "Parse error", details: e.message }, status: :unprocessable_entity
      end

      # Queue background job
      job = ManifestApplyJob.perform_later(@project.id, content)

      render json: {
        job_id: job.job_id,
        status: "queued",
        message: "Manifest changes are being applied"
      }
    end

    # GET /api/projects/:project_id/manifest/status
    def status
      render json: {
        synced: @project.manifest_synced?,
        drift_detected: @project.manifest_drift_detected,
        last_synced_at: @project.manifest_last_synced_at,
        last_applied_at: @project.manifest_last_applied_at,
        format: @project.manifest_format,
        has_manifest: @project.manifest_content.present?
      }
    end

    private

    def set_and_authorize_project!
      @project = scoped_projects.find_by(id: params[:project_id])
      return render json: { error: "Project not found" }, status: :not_found unless @project
      authorize_project!(@project, action: :update)
    end

    def manifest_params
      params.require(:manifest).permit(:content, :format)
    rescue ActionController::ParameterMissing
      params.permit(:content, :format)
    end

    def detect_format(content)
      stripped = content.to_s.strip
      return "app.json" if stripped.start_with?("{") && (stripped.include?("buildpacks") || stripped.include?("formation"))
      "raildock.toml"
    end
  end
end
