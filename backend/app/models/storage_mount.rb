class StorageMount < ApplicationRecord
  belongs_to :service

  validates :host_path, presence: true, uniqueness: { scope: :service_id }
  validates :container_path, presence: true
end
