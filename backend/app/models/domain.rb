class Domain < ApplicationRecord
  belongs_to :service

  validates :hostname, presence: true, uniqueness: { scope: :service_id }
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
end
