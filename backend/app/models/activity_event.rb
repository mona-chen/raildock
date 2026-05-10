class ActivityEvent < ApplicationRecord
  belongs_to :project

  validates :action, inclusion: { in: %w[deployed stopped started scaled linked unlinked created destroyed] }
  validates :message, presence: true

  enum :action, {
    deployed: "deployed",
    stopped: "stopped",
    started: "started",
    scaled: "scaled",
    linked: "linked",
    unlinked: "unlinked",
    created: "created",
    destroyed: "destroyed"
  }, prefix: true

  default_scope { order(created_at: :desc) }

  def timestamp
    created_at&.iso8601
  end

  def as_json(options = {})
    super(options.merge(methods: [:timestamp]))
  end
end
