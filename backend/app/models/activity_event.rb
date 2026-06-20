class ActivityEvent < ApplicationRecord
  belongs_to :project

  validates :action, inclusion: { in: %w[deployed stopped started restarted scaled linked unlinked created destroyed warning rebuilt] }
  validates :message, presence: true

  enum :action, {
    deployed: "deployed",
    stopped: "stopped",
    started: "started",
    restarted: "restarted",
    scaled: "scaled",
    linked: "linked",
    unlinked: "unlinked",
    created: "created",
    destroyed: "destroyed",
    warning: "warning",
    rebuilt: "rebuilt"
  }, prefix: true

  default_scope { order(created_at: :desc) }
  after_create_commit :broadcast_created

  def timestamp
    created_at&.iso8601
  end

  def as_json(options = {})
    super(options.merge(methods: [ :timestamp ]))
  end

  private
    def broadcast_created
      ProjectChannel.broadcast_to(project, { type: "activity", project_id: project_id, event: as_json, timestamp: Time.current.iso8601 })
    rescue => error
      Rails.logger.warn "Activity realtime broadcast failed for #{id}: #{error.message}"
    end
end
