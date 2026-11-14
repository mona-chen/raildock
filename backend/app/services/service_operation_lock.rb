# Shared across HTTP handlers and workers. Project-wide destruction/reconciliation
# takes an exclusive project lock; service operations share that project lock
# and serialize individually. Nonblocking acquisition avoids lock-order deadlocks.
class ServiceOperationLock
  class Busy < StandardError; end

  def self.with(service)
    with_project(service.project_id) do
      with_key("service", service.id) { yield }
    end
  end

  def self.with_project(project, exclusive: false)
    id = project.respond_to?(:id) ? project.id : project
    return yield unless id

    with_key("project", id, shared: !exclusive) { yield }
  end

  def self.with_key(kind, id, shared: false)
    ApplicationRecord.connection_pool.with_connection do |connection|
      key = "hashtextextended('raildock:#{kind}:#{Integer(id)}', 0)"
      suffix = shared ? "_shared" : ""
      acquired = connection.select_value("SELECT pg_try_advisory_lock#{suffix}(#{key})")
      raise Busy, "Another operation is running for this resource" unless acquired

      begin
        yield
      ensure
        connection.select_value("SELECT pg_advisory_unlock#{suffix}(#{key})")
      end
    end
  end
  private_class_method :with_key
end
