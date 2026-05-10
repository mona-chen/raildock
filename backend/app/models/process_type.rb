class ProcessType < ApplicationRecord
  belongs_to :service

  validates :name, presence: true, uniqueness: { scope: :service_id }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
end
