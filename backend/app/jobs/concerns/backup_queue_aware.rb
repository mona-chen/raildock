# frozen_string_literal: true

# Guards shared by the recurring backup jobs.
#
# Solid Queue enqueues a recurring task on every tick even when earlier runs are
# still waiting, so a destination that stops accepting writes turns "once a
# minute" into thousands of queued jobs — all of which would execute once the
# queue unblocks. Two guards keep that bounded:
#
#   * backpressure  — stop adding work while the backups queue is already deep
#   * single-flight — never enqueue a second child for a config whose previous
#                     child is still waiting or running
#
# Both are no-ops outside Solid Queue, so the test adapter is unaffected.
module BackupQueueAware
  extend ActiveSupport::Concern

  # How many ready jobs the backups queue may hold before the recurring jobs
  # stop adding more. Large enough for a normal burst of services, small enough
  # that a wedged endpoint cannot grow the queue without bound.
  BACKLOG_LIMIT = 200

  private
    def backups_backlogged?
      return false unless solid_queue?

      SolidQueue::ReadyExecution
        .where(queue_name: "backups")
        .limit(BACKLOG_LIMIT)
        .count >= BACKLOG_LIMIT
    end

    # A child for these exact arguments is either ready, scheduled, blocked or
    # running. Failed executions are excluded: they will not retry on their own,
    # so treating them as in-flight would wedge the config forever.
    def backup_job_enqueued?(job_class, *arguments)
      return false unless solid_queue?

      SolidQueue::Job
        .where(class_name: job_class.name, finished_at: nil)
        .where("arguments LIKE ?", "%\"arguments\":#{arguments.to_json}%")
        .where.not(id: SolidQueue::FailedExecution.select(:job_id))
        .exists?
    end

    def solid_queue?
      defined?(SolidQueue) &&
        ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
    end
end
