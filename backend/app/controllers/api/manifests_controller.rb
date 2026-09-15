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

      # Validate — use repaired content if parser fixed syntax issues
      schema_content = desired.repaired_content || content
      parsed = JSON.parse(schema_content) rescue TomlRB.parse(schema_content)
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
      }.merge(removals_payload(reconciler, content))
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
      }.merge(removals_payload(reconciler, content))
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

      # Validate — use repaired content if parser fixed syntax issues
      schema_content = desired.repaired_content || content
      parsed = JSON.parse(schema_content) rescue TomlRB.parse(schema_content)
      validation = ManifestSchema.validate(parsed)
      unless validation.success?
        return render json: { error: "Validation failed", details: validation.errors }, status: :unprocessable_entity
      end

      reconciler = ManifestReconciler.new(@project, desired)
      reconciler.diff

      # Destroying services requires an explicit, reviewable confirmation.
      # Everything else applies normally.
      decision = removal_decision(reconciler, content)
      unless decision[:allowed]
        return render json: {
          error: decision[:error],
          code: "removals_required",
          actionable: true,
          removals: decision[:removals],
          removal_token: RemovalConfirmation.issue(
            project: @project,
            digest: RemovalConfirmation.digest_for(content),
            removals: decision[:removals].map { |removal| removal[:service_name] }
          )
        }, status: :precondition_required
      end

      # Queue background job
      job = ManifestApplyJob.perform_later(@project.id, content, decision[:options])

      render json: {
        job_id: job.job_id,
        status: "queued",
        message: decision[:options][:allow_removals] ?
          "Manifest changes are being applied, including #{decision[:removals].length} confirmed removal(s)" :
          "Manifest changes are being applied",
        removals: decision[:removals]
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

    # What this manifest would destroy, plus the token the client must echo
    # back to authorise it. Empty for non-destructive changes.
    def removals_payload(reconciler, content)
      removals = reconciler.removal_plan
      return { removals: [], requires_removal_confirmation: false } if removals.empty?

      {
        removals: removals,
        requires_removal_confirmation: true,
        removal_token: RemovalConfirmation.issue(
          project: @project,
          digest: RemovalConfirmation.digest_for(content),
          removals: removals.map { |removal| removal[:service_name] }
        ),
        removal_digest: RemovalConfirmation.digest_for(content)
      }
    end

    def removal_decision(reconciler, content)
      removals = reconciler.removal_plan
      return { allowed: true, removals: [], options: {} } if removals.empty?

      names = removals.map { |removal| removal[:service_name] }
      confirmed = ActiveModel::Type::Boolean.new.cast(params[:confirm_removals])
      unless confirmed
        return {
          allowed: false,
          removals: removals,
          error: "This manifest removes #{names.length} service(s): #{names.join(', ')}. Confirm the removal before RailDock deletes them."
        }
      end

      begin
        RemovalConfirmation.verify!(
          token: params[:removal_confirmation_token],
          project: @project,
          digest: RemovalConfirmation.digest_for(content),
          removals: names
        )
      rescue RemovalConfirmation::InvalidConfirmation => error
        return { allowed: false, removals: removals, error: error.message }
      end

      {
        allowed: true,
        removals: removals,
        options: {
          allow_removals: true,
          force_destroy_data: ActiveModel::Type::Boolean.new.cast(params[:force_destroy_data]) || false
        }
      }
    end

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

      # app.json: JSON with buildpacks/formation (must come BEFORE the
      # Railway JSON check, since both start with "{")
      return "app.json" if stripped.start_with?("{") && (stripped.include?("buildpacks") || stripped.include?("formation"))

      # railway.json: JSON with build or deploy top-level keys
      return "railway.json" if stripped.start_with?("{") && (stripped.match?(/["']build["']\s*:/) || stripped.match?(/["']deploy["']\s*:/))

      # railway.toml: TOML with [build] or [deploy] section
      return "railway.toml" if stripped.match?(/\A\s*\[build\]/) || stripped.match?(/\A\s*\[deploy\]/)

      "raildock.toml"
    end
  end
end
