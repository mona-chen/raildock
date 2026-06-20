module Api
  class RepositoryImportsController < BaseController
    include Authorizable

    before_action :set_project

    def preview
      git_source = scoped_git_source
      result = RepositoryDiscovery.new(
        git_source: git_source,
        repository: params.require(:repository),
        branch: params[:branch]
      ).call

      render json: result.as_json.merge(
        snapshot_token: snapshot_verifier.generate(snapshot_payload(result), expires_in: 15.minutes)
      )
    rescue ManifestParser::ParseError => error
      render json: { error: error.message }, status: :unprocessable_entity
    rescue Octokit::Error => error
      render json: { error: "Repository inspection failed: #{error.message}" }, status: :bad_gateway
    end

    def apply
      payload = snapshot_verifier.verify(params.require(:snapshot_token))
      raise ActiveSupport::MessageVerifier::InvalidSignature unless payload.fetch("project_id") == @project.id
      canonical = payload.fetch("canonical_manifest")
      parsed = JSON.parse(canonical)
      apply_builder_overrides!(parsed)
      canonical = JSON.pretty_generate(parsed)
      validation = ManifestSchema.validate(parsed)
      return render json: { error: "Validation failed", details: validation.errors }, status: :unprocessable_entity unless validation.success?

      ManifestParser.parse(canonical, filename: "raildock.json")
      @project.update!(
        manifest_content: canonical,
        manifest_format: "raildock.json",
        manifest_last_synced_at: Time.current,
        manifest_drift_detected: false
      )
      job = ManifestApplyJob.perform_later(@project.id, canonical)

      render json: {
        status: "queued",
        job_id: job.job_id,
        commit_sha: payload.fetch("commit_sha"),
        service_count: parsed.fetch("services").length
      }, status: :accepted
    rescue ActiveSupport::MessageVerifier::InvalidSignature, KeyError, JSON::ParserError
      render json: { error: "This repository review is invalid or expired. Scan the repository again." }, status: :unprocessable_entity
    end

    private
      def set_project
        @project = scoped_projects.find(params[:project_id])
        authorize_project!(@project, action: :update)
      end

      def scoped_git_source
        source = GitSource.find(params.require(:git_source_id))
        allowed = if @project.organization_id.present?
          source.organization_id == @project.organization_id && current_user.organizations.exists?(id: @project.organization_id)
        else
          source.user_id == @project.user_id || (source.user_id.nil? && current_user.admin?)
        end
        raise ActiveRecord::RecordNotFound unless allowed

        source
      end

      def snapshot_verifier
        @snapshot_verifier ||= ActiveSupport::MessageVerifier.new(
          Rails.application.secret_key_base,
          digest: "SHA256",
          serializer: JSON,
          url_safe: true
        )
      end

      def snapshot_payload(result)
        {
          project_id: @project.id,
          repository: result.repository,
          branch: result.branch,
          commit_sha: result.commit_sha,
          canonical_manifest: result.canonical_manifest
        }
      end

      def apply_builder_overrides!(manifest)
        overrides = params[:builder_overrides]
        return unless overrides.respond_to?(:to_unsafe_h) || overrides.is_a?(Hash)

        overrides = overrides.to_unsafe_h if overrides.respond_to?(:to_unsafe_h)
        services = manifest.fetch("services").index_by { |service| service.fetch("name") }
        overrides.each do |name, builder|
          raise KeyError unless services.key?(name) && ManifestSchema::BUILDERS.include?(builder)

          services.fetch(name)["builder"] = builder
        end
      end
  end
end
