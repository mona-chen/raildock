class Backup < ApplicationRecord
  belongs_to :service

  validates :status, inclusion: { in: %w[pending running completed failed] }

  scope :recent, -> { order(created_at: :desc) }
end
