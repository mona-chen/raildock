module Api
  class RepositoryImportsController < BaseController
    include Authorizable

    class InvalidServiceSelection < StandardError; end

    before_action :set_project

    def preview
      git_source = scoped_git_source
      result = RepositoryDiscovery.new(
        git_source: git_source,
        repository: params.require(:repository),
        branch: params[:branch]
      ).call

      manifest_content, manifest_format = import_manifest_content(
        canonical_manifest: result.canonical_manifest,
        original_format: result.original_format,
        original_content: result.original_content
      )

      render json: result.as_json.merge(
        snapshot_token: snapshot_verifier.generate(snapshot_payload(result), expires_in: 15.minutes)
      ).merge(
        removal_preview(manifest_content, manifest_format, digest: result.commit_sha)
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

      manifest_content, manifest_format = import_manifest_content(
        canonical_manifest: canonical,
        original_format: payload["format"] || "raildock.json",
        original_content: payload["original_content"]
      )

      ManifestParser.parse(manifest_content, filename: manifest_format, source: :repository)

      service_names, expanded_services = service_selection(parsed)

      # Importing a repository must never delete unrelated services. Services
      # that exist today but are missing from the imported manifest are kept
      # unless the user confirmed that exact list for this commit.
      removals = removal_plan_for(manifest_content, manifest_format)
      confirmed = removals_confirmed?(removals, digest: payload.fetch("commit_sha"))

      adopted = adopt_manifest!(manifest_content, manifest_format, removals: removals, confirmed: confirmed)

      options = { allow_removals: confirmed, force_destroy_data: force_destroy_data? }
      options[:service_names] = service_names if service_names

      job = ManifestApplyJob.perform_later(
        @project.id,
        manifest_content,
        options
      )

      render json: {
        status: "queued",
        job_id: job.job_id,
        commit_sha: payload.fetch("commit_sha"),
        service_count: service_names ? service_names.length : parsed.fetch("services").length,
        services: service_names,
        expanded_services: expanded_services,
        removals: removals,
        removals_confirmed: confirmed,
        manifest_adopted: adopted
      }, status: :accepted
    rescue InvalidServiceSelection => error
      render json: { error: error.message }, status: :unprocessable_entity
    rescue ActiveSupport::MessageVerifier::InvalidSignature, KeyError, JSON::ParserError
      render json: { error: "This repository review is invalid or expired. Scan the repository again." }, status: :unprocessable_entity
    end

    private
      def import_manifest_content(canonical_manifest:, original_format:, original_content:)
        format = original_format == "raildock.toml" ? "raildock.toml" : "raildock.json"
        content = original_content.presence || canonical_manifest
        [ content, format ]
      end

      # Services that exist today but are absent from the manifest an import
      # would apply.
      def removal_plan_for(content, format)
        desired = ManifestParser.parse(content, filename: format, source: :repository)
        reconciler = ManifestReconciler.new(@project, desired)
        reconciler.diff
        reconciler.removal_plan
      rescue ManifestParser::ParseError
        []
      end

      # Replacing the project's manifest with the imported one is only safe when
      # the import still describes everything the project owns. When it omits
      # services the user has not agreed to remove, storing it would silently
      # shrink the project's source of truth and reset the drift flag — hiding
      # the fact that the manifest no longer matches the project. Keep the
      # current manifest, apply the additive changes only, and report drift.
      def adopt_manifest!(content, format, removals:, confirmed:)
        if removals.any? && !confirmed
          kept = removals.map { |removal| removal[:service_name] }
          @project.update!(manifest_drift_detected: true)
          ActivityEvent.create!(
            project: @project,
            service_name: kept.first,
            action: :warning,
            message: "Kept the existing manifest for #{@project.name}: the imported manifest omits #{kept.join(', ')}. " \
                     "Applied without removing them, so the manifest editor now reports drift."
          )
          return false
        end

        @project.update!(
          manifest_content: content,
          manifest_format: format,
          manifest_last_synced_at: Time.current,
          manifest_drift_detected: false
        )
        true
      end

      def removal_preview(content, format, digest:)
        removals = removal_plan_for(content, format)
        return { removals: [], removals_require_confirmation: false } if removals.empty?

        {
          removals: removals,
          removals_require_confirmation: true,
          removal_token: RemovalConfirmation.issue(
            project: @project,
            digest: digest,
            removals: removals.map { |removal| removal[:service_name] }
          )
        }
      end

      def removals_confirmed?(removals, digest:)
        return false if removals.empty?
        return false unless ActiveModel::Type::Boolean.new.cast(params[:confirm_removals])

        RemovalConfirmation.verify!(
          token: params[:removal_confirmation_token],
          project: @project,
          digest: digest,
          removals: removals.map { |removal| removal[:service_name] }
        )
        true
      rescue RemovalConfirmation::InvalidConfirmation
        false
      end

      def force_destroy_data?
        ActiveModel::Type::Boolean.new.cast(params[:force_destroy_data]) || false
      end

      # A repository import may deploy only the detected services the user
      # picked. Anything left unselected is untouched — never a removal — and
      # dependencies that do not exist yet are pulled into the selection so a
      # selected app can actually boot.
      def service_selection(manifest)
        return [ nil, [] ] unless params.key?(:services)

        requested = Array(params[:services]).map { |name| name.to_s.strip }.reject(&:blank?).uniq
        raise InvalidServiceSelection, "Select at least one service to deploy" if requested.empty?

        declared = manifest.fetch("services", []).index_by { |service| service.fetch("name").to_s }
        unknown = requested - declared.keys
        raise InvalidServiceSelection, "Unknown services: #{unknown.join(', ')}" if unknown.any?

        existing = @project.services.where(name: declared.keys).pluck(:name).to_set
        expanded = requested.dup
        queue = requested.dup
        until queue.empty?
          name = queue.shift
          dependencies_for(manifest, name).each do |dependency|
            next unless declared.key?(dependency)
            next if expanded.include?(dependency)
            next if existing.include?(dependency) # already owned by the project; leave it alone

            expanded << dependency
            queue << dependency
          end
        end

        [ expanded, expanded - requested ]
      end

      def dependencies_for(manifest, name)
        service = manifest.fetch("services", []).find { |candidate| candidate.fetch("name").to_s == name }
        depends_on = Array(service&.dig("depends_on")).map(&:to_s)
        linked = Array(manifest["links"]).select { |link| link["from"].to_s == name }.map { |link| link["to"].to_s }
        (depends_on + linked).uniq
      end

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
          canonical_manifest: result.canonical_manifest,
          format: result.original_format,
          original_content: result.original_content
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
