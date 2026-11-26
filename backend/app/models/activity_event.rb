class ActivityEvent < ApplicationRecord
  belongs_to :project
  belongs_to :api_token, optional: true

  validates :action, inclusion: { in: %w[deployed stopped started restarted scaled linked unlinked created destroyed warning rebuilt updated] }
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
    rebuilt: "rebuilt",
    updated: "updated"
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
      RealtimeBroadcaster.project(project, { type: "activity", project_id: project_id, event: as_json, timestamp: Time.current.iso8601 })
    end
end
