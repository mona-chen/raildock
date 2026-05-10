class EnvironmentVariable < ApplicationRecord
  belongs_to :service

  validates :key, presence: true, uniqueness: { scope: :service_id }
  validates :value, presence: true
end
