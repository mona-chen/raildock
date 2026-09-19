# frozen_string_literal: true

require "shellwords"

# Reconciles a Domain's routing with Dokku on the service's host.
#
# Domain mutations used to issue one SSH command per call straight from the
# controller and only *after* the database row had been committed. On a slow or
# unhappy host that produced the worst outcome: an error response to the user
# while the change was already half-applied on the server, plus a fresh SSH
# handshake for every command (the connection storm that made adding a domain
# feel slow).
#
# This object funnels a mutation through a single SSH session, resolves the
# container port from one place, and returns a Result instead of raising, so the
# controller can roll the database back to match the host.
class DomainSync
  Result = Struct.new(:success, :output, keyword_init: true) do
    def success? = success
    def failure? = !success
  end

  OK = Result.new(success: true, output: "")

  attr_reader :service

  def initialize(service, engine: nil)
    @service = service
    @engine = engine
  end

  # Whether there is a host to talk to. When there is not (no server, or no SSH
  # key yet) the caller still persists the domain; Dokku is reconciled on the
  # next deploy.
  def available?
    server.present? && server.ssh_key.present?
  end

  # Publish a new domain's hostname and point the app's port mapping at it.
  def add(domain)
    return OK unless available?

    within_session do
      result = publish_hostname(domain)
      return failure(result[:output]) unless result[:success]

      apply_routing(target_port: domain.resolved_target_port, https: domain.ssl)
    end
  end

  # Apply an edit to an existing domain, moving or removing the old hostname
  # first so a rename never leaves a stale vhost behind.
  def replace(domain, previous_hostname:)
    return OK unless available?

    within_session do
      if previous_hostname.to_s != domain.hostname.to_s
        result = unpublish_hostname(previous_hostname)
        return failure(result[:output]) unless result[:success]
      end

      result = publish_hostname(domain)
      return failure(result[:output]) unless result[:success]

      apply_routing(target_port: domain.resolved_target_port, https: domain.ssl)
    end
  end

  # Withdraw a domain's hostname, then re-point the remaining routing.
  def remove(domain)
    return OK unless available?

    within_session do
      result = unpublish_hostname(domain.hostname)
      return failure(result[:output]) unless result[:success]

      remaining_https = service.domains.where.not(id: domain.id).where(ssl: true).exists?
      apply_routing(target_port: service.reload.effective_port, https: remaining_https)
    end
  end

  private

  def within_session(&block)
    engine.with_session { block.call }
  end

  def publish_hostname(domain)
    if domain.wildcard?
      labels = TraefikLabelBuilder.new(service, domain).build_labels
      labels.each do |key, value|
        result = engine.run("traefik:labels:add #{escape(app_name)} #{escape(key)} #{escape(value)}")
        return result unless result[:success]
      end
      { success: true, output: "" }
    else
      engine.domain_add(app_name, domain.hostname)
    end
  end

  def unpublish_hostname(hostname)
    return engine.domain_remove(app_name, hostname) unless hostname.to_s.start_with?("*.")

    # Wildcards have no VHOST entry — each label was added by hand, so find the
    # labels that reference this domain's router and drop them individually.
    router_name = "#{app_name}-#{hostname.to_s.sub(/\A\*\./, '').parameterize}"
    result = engine.traefik_show_config(app_name)
    return result unless result[:success]

    result[:output].each_line do |line|
      next unless line.include?(router_name)

      key = line.split("=").first&.strip
      next if key.blank?

      removal = engine.run("traefik:labels:remove #{escape(app_name)} #{escape(key)}")
      return removal unless removal[:success]
    end
    { success: true, output: "" }
  end

  def apply_routing(target_port:, https:)
    return refresh_external_proxy if server.external_proxy?

    result = apply_port_mapping(target_port, https)
    return failure(result[:output]) unless result[:success]

    rebuild_for_port_change!(target_port)
  end

  def apply_port_mapping(target_port, https)
    mappings = [ "http:80:#{target_port.to_i}" ]
    mappings << "https:443:#{target_port.to_i}" if https
    engine.ports_set(app_name, *mappings)
  end

  # An app is told which port to listen on through its Dokku port mapping, so a
  # change of container port only takes effect after a rebuild. Skip it when the
  # port is unchanged — that rebuild was the slow part of adding a domain.
  def rebuild_for_port_change!(target_port)
    return OK unless service.running?
    return OK if target_port.to_i == service.detected_port.to_i

    result = engine.ps_rebuild(app_name)
    return failure(result[:output]) unless result[:success]

    service.update!(detected_port: target_port.to_i)
    OK
  end

  def refresh_external_proxy
    host_engine = HostEngine.new(server)
    result = host_engine.with_session do
      ExternalProxyConfigurator.new(service.reload, engine, host_engine).apply!
    end
    return failure(result[:output]) unless result[:success]
    return OK unless service.running?

    rebuild = engine.ps_rebuild(app_name)
    return failure(rebuild[:output]) unless rebuild[:success]

    OK
  end

  def failure(output)
    Result.new(success: false, output: output.to_s)
  end

  def engine
    @engine ||= DokkuEngine.new(server)
  end

  def server
    @server ||= service.project&.server
  end

  def app_name
    service.dokku_app_name
  end

  def escape(value)
    Shellwords.escape(value.to_s)
  end
end
