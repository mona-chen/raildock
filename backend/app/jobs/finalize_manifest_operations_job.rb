class FinalizeManifestOperationsJob < ApplicationJob
  queue_as :default

  # Also scheduled: a worker interrupted after a deployment completed must not
  # leave its manifest continuation stranded.
  def perform
    ManifestOperation.where(status: "waiting").find_each do |operation|
      operation.finalize_if_ready!
    rescue ServiceOperationLock::Busy
      next # Leave waiting; the next scheduler tick retries safely.
    rescue => error
      operation.update!(status: "failed", error: LogRedactor.redact(error.message), completed_at: Time.current)
    end
  end
end
