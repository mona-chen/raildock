class MonitoringIncident < ApplicationRecord
  belongs_to :server
  scope :active, -> { where(resolved_at: nil).where(state: "firing") }
end
