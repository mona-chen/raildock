module Api
  class DomainsController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!, only: [ :create, :destroy ]
    before_action :set_domain_and_authorize!, only: [ :update ]

    # POST /api/services/:service_id/domains
    #
    # Idempotent: re-submitting the same domain (a double click, a retried
    # request) returns the existing record with 200 instead of an error. A
    # *conflicting* domain is a 409 the UI can act on, and a host that refuses
    # the change rolls the record back so the UI never shows a domain that is
    # not actually routed.
    def create
      hostname = normalize_hostname_param(domain_params[:hostname])
      return render_error("Hostname is required") if hostname.blank?

      if (existing = find_domain(hostname))
        return render json: existing, status: :ok if matches_request?(existing)

        return render json: {
          error: "#{hostname} is already routed to this service on port #{existing.resolved_target_port}. Edit it instead of adding it again.",
          code: "domain_exists",
          domain: existing
        }, status: :conflict
      end

      attributes = attributes_for(hostname)
      domain = @service.domains.create!(attributes.merge(ssl_status: ssl_status_for(attributes[:ssl])))
      result = domain_sync.add(domain)
      return render_sync_failure(:add, domain, result) if result.failure?

      render json: domain, status: :created
    end

    # PATCH /api/domains/:id  (shallow route off `resources :services`)
    def update
      domain = @domain
      hostname = normalize_hostname_param(domain_params[:hostname].presence || domain.hostname)
      return render_error("Hostname is required") if hostname.blank?

      if (clash = find_domain(hostname)) && clash.id != domain.id
        return render json: {
          error: "#{hostname} is already routed to this service. Edit that domain instead.",
          code: "domain_exists",
          domain: clash
        }, status: :conflict
      end

      previous = domain.attributes
      ssl_changed = domain_params.key?(:ssl) && cast_bool(domain_params[:ssl]) != domain.ssl

      domain.assign_attributes(attributes_for(hostname, fallback: domain))
      domain.ssl_status = ssl_status_for(domain.ssl) if ssl_changed
      return render_validation_errors(domain) unless domain.valid?

      result = domain_sync.replace(domain, previous_hostname: previous["hostname"])
      return render_sync_failure(:update, domain, result, previous: previous) if result.failure?

      domain.save!
      render json: domain
    end

    # DELETE /api/services/:service_id/domains/*hostname
    #
    # Idempotent: deleting a domain that is already gone succeeds quietly. The
    # record is only dropped once the host confirms it stopped routing, so a
    # failed removal leaves something the UI can retry.
    def destroy
      hostname = normalize_hostname_param(params[:hostname])
      domain = find_domain(hostname)
      return head :no_content unless domain

      result = domain_sync.remove(domain)
      return render_sync_failure(:remove, domain, result) if result.failure?

      domain.destroy!
      head :no_content
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end

    def set_domain_and_authorize!
      @domain = Domain.find(params[:id])
      @service = @domain.service
      authorize_service!(@service, action: :update)
    end

    def domain_params
      params.permit(:hostname, :port, :target_port, :ssl, :letsencrypt, :challenge_type)
    end

    def normalize_hostname_param(value)
      value.to_s
        .strip
        .sub(/\Ahttps?:\/\/?/i, "")
        .sub(/:\d+\z/, "")
        .sub(/\/.*\z/, "")
        .downcase
    end

    def find_domain(hostname)
      return nil if hostname.blank?

      @service.domains.where("lower(hostname) = ?", hostname.to_s.downcase).first
    end

    # The stored attributes for a create/update. `fallback` is the existing
    # domain on an edit, so a request that only changes the hostname does not
    # silently reset SSL, letsencrypt, or the port.
    #
    # target_port stays nil unless the user asked for a specific port, so the
    # domain follows the app instead of freezing whatever the port happened to
    # be at the time.
    def attributes_for(hostname, fallback: nil)
      wildcard = hostname.start_with?("*.")
      ssl = if domain_params.key?(:ssl)
        cast_bool(domain_params[:ssl])
      else
        fallback ? fallback.ssl : true
      end
      ssl = false if Domain::MAGIC_DOMAINS.any? { |m| hostname.end_with?(".#{m}") }

      {
        hostname: hostname,
        wildcard: wildcard,
        ssl: ssl,
        port: domain_params[:port].presence&.to_i || fallback&.port || (ssl ? 443 : 80),
        letsencrypt: letsencrypt_for(ssl, fallback),
        target_port: domain_params.key?(:target_port) ? domain_params[:target_port].presence&.to_i : fallback&.target_port,
        challenge_type: wildcard ? "dns" : (domain_params[:challenge_type].presence || fallback&.challenge_type || "http")
      }
    end

    def letsencrypt_for(ssl, fallback)
      return false unless ssl
      return cast_bool(domain_params[:letsencrypt]) if domain_params.key?(:letsencrypt)

      fallback ? fallback.letsencrypt : true
    end

    # True when the request would produce the record that already exists — a
    # genuine duplicate rather than a conflicting edit.
    def matches_request?(existing)
      desired = attributes_for(existing.hostname)
      resolved = desired[:target_port].presence || @service.effective_port

      existing.ssl == desired[:ssl] && existing.resolved_target_port.to_i == resolved.to_i
    end

    def render_sync_failure(action, domain, result, previous: nil)
      revert(action, domain, previous)
      Rails.logger.error "Domain #{action} failed for #{@service.dokku_app_name}: #{result.output}"

      render_error("Failed to #{action} #{domain.hostname}: #{result.output.to_s.strip.presence || 'the server rejected the change'}")
    end

    # Undo the host-side change so Dokku and the database never disagree.
    def revert(action, domain, previous)
      case action
      when :add
        domain_sync.remove(domain)
        domain.destroy
      when :update
        return if previous.blank?

        # The row was never saved, so the database is already correct — only the
        # host needs putting back. Rebuild from the row's own snapshot so the
        # revert does not inherit the values the host just rejected.
        restored = @service.domains.new(previous.except("id", "created_at", "updated_at"))
        domain_sync.replace(restored, previous_hostname: domain.hostname)
      end
    rescue => e
      Rails.logger.error "Failed to revert domain #{action} for #{@service.dokku_app_name}: #{e.message}"
    end

    def render_validation_errors(domain)
      render json: { error: domain.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    def render_error(message)
      render json: { error: message }, status: :unprocessable_entity
    end

    def ssl_status_for(ssl)
      ssl ? "pending" : "none"
    end

    def cast_bool(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    def domain_sync
      @domain_sync ||= DomainSync.new(@service)
    end
  end
end
