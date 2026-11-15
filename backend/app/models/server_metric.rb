class ServerMetric < ApplicationRecord
  belongs_to :server

  def self.prune_older_than!(cutoff = ObservabilitySettings.retention_days.days.ago)
    where("sampled_at < ?", cutoff).in_batches.delete_all
  end
end
