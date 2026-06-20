class StorageMount < ApplicationRecord
  belongs_to :service

  validates :host_path, presence: true, uniqueness: { scope: :service_id }
  validates :container_path, presence: true
  validates :container_path, format: { with: %r{\A/[^\0]*\z}, message: "must be an absolute container path" }
  validate :host_path_is_named_volume_or_absolute

  private
    def host_path_is_named_volume_or_absolute
      return if host_path.blank? || host_path.start_with?("/") || host_path.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/)

      errors.add(:host_path, "must be an absolute path or a named volume")
    end
end
