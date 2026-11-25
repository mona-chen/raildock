# Called only after the project's explicit confirmation and destruction snapshot.
# Host operations are not transactional: retries must accept resources already gone.
class ProjectResourceTeardown
  def initialize(project, engine: DokkuEngine.new(project.server))
    @project = project
    @engine = engine
  end

  def call
    datastores, apps = @project.services.to_a.partition { |service| service.subtype_record&.has_capability?(:destroy) }
    owned_apps = apps.map(&:dokku_app_name)
    links = {}
    # Preflight all datastores before removing or unlinking anything. A link to
    # an app outside this project is not ours to sever, even with --force.
    datastores.each do |service|
      result = @engine.datastore_links(service)
      return [ "#{service.name}: could not verify datastore links" ] unless result[:success]
      links[service.id] = Array(result[:apps])
      foreign = links[service.id] - owned_apps
      return [ "#{service.name}: still linked to apps outside this project (#{foreign.join(', ')}). Unlink or move those dependencies explicitly first." ] if foreign.any?
    end
    datastores.each do |service|
      links.fetch(service.id).each do |app_name|
        result = @engine.datastore_unlink(service, app_name)
        return [ "#{service.name}: failed to unlink #{app_name}" ] unless result&.dig(:success)
      end
    end
    # Never remove a datastore while an app that was meant to be removed failed.
    failures = apps.filter_map do |service|
      result = @engine.app_destroy(service.dokku_app_name)
      failure(service, result, "App")
    end
    return failures if failures.any?
    datastores.filter_map do |service|
      result = @engine.datastore_destroy(service)
      failure(service, result, "Service")
    end
  end

  private

  def failure(service, result, type)
    return if result&.dig(:success)
    output = (result&.dig(:output) || result&.dig(:error)).to_s.strip
    # Exact resource identity and error shape only: permission/SSH errors must
    # never be interpreted as proof that a resource is absent.
    return if output.match?(/\A\s*!?\s*#{type}\s+['"]?#{Regexp.escape(service.dokku_app_name)}['"]?\s+does not exist[.!]?\s*\z/i)
    "#{service.name}: #{output.presence || 'host operation failed'}"
  end
end
