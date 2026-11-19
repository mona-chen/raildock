# A durable pointer to asynchronous work started through the API.
#
# The operation does not re-implement the work: it names the authoritative
# record (a Deployment, a ManifestOperation, or the project being deleted) and
# derives its status from it. `status` and `completed_at` are only stored when
# no subject can report a terminal outcome — an additive manifest apply, or a
# deletion whose project row no longer exists.
class Operation < ApplicationRecord
  KINDS = %w[deploy restart rollback manifest_apply project_deletion].freeze
  STATUSES = %w[pending running succeeded failed cancelled].freeze

  belongs_to :organization
  belongs_to :project, optional: true
  belongs_to :service, optional: true
  belongs_to :api_token, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :idempotency_key, length: { maximum: 140 }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :for_organization, ->(organization) { where(organization: organization) }

  def status
    derived_status || self[:status] || "pending"
  end

  def started_at
    case subject
    when Deployment then subject.started_at || subject.created_at
    when ManifestOperation then subject.created_at
    else self[:created_at]
    end
  end

  def completed_at
    case subject
    when Deployment, ManifestOperation then subject.completed_at
    else self[:completed_at]
    end
  end

  def error
    case subject
    when ManifestOperation then subject.error
    when Project then kind == "project_deletion" ? subject.deletion_error : nil
    else self[:error]
    end
  end

  private

  def derived_status
    case subject
    when Deployment then deployment_status(subject)
    when ManifestOperation then manifest_status(subject)
    when Project then project_deletion_status(subject)
    end
  end

  def deployment_status(deployment)
    case deployment.status
    when "pending", "building", "deploying" then "running"
    when "succeeded", "failed", "cancelled" then deployment.status
    end
  end

  def manifest_status(operation)
    case operation.status
    when "waiting", "finalizing" then "running"
    when "succeeded", "failed" then operation.status
    end
  end

  def project_deletion_status(project)
    return unless kind == "project_deletion"

    case project.deletion_status
    when "queued" then "pending"
    when "running" then "running"
    when "failed" then "failed"
    end
  end
end
