# frozen_string_literal: true

# A single resource-usage sample for a service, captured by MetricsSamplerJob.
class ServiceMetric < ApplicationRecord
  belongs_to :service

  scope :since, ->(time) { where(sampled_at: time..) }
  scope :recent_first, -> { order(sampled_at: :desc) }

  # 30-day retention. Pruned by MetricsSamplerJob so the table stays bounded.
  RETENTION = 30.days

  def self.prune_older_than!(cutoff = RETENTION.ago)
    where("sampled_at < ?", cutoff).delete_all
  end
end
