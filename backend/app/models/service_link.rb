class ServiceLink < ApplicationRecord
  belongs_to :from_service, class_name: "Service"
  belongs_to :to_service, class_name: "Service"

  validates :from_service_id, uniqueness: { scope: :to_service_id }
  validate :cannot_link_to_self

  private

  def cannot_link_to_self
    errors.add(:to_service, "cannot link to itself") if from_service_id == to_service_id
  end
end
