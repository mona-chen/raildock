class StorageMount < ApplicationRecord
  belongs_to :service

  enum :kind, {
    volume: "volume",
    bind: "bind",
    tmpfs: "tmpfs"
  }, prefix: true

  validates :host_path, presence: true, uniqueness: { scope: :service_id }
  validates :container_path, presence: true
  validates :container_path, format: { with: %r{\A/[^\0]*\z}, message: "must be an absolute container path" }
  validates :kind, inclusion: { in: kinds.keys }
  validate :host_path_matches_kind

  before_validation :normalize_kind

  private
    def normalize_kind
      if kind.blank?
        self.kind = host_path.present? && host_path.start_with?("/") ? "bind" : "volume"
      end
    end

    def host_path_matches_kind
      return if host_path.blank?

      case kind
      when "bind"
        unless host_path.start_with?("/")
          errors.add(:host_path, "bind mounts must be absolute host paths")
        end
      when "volume"
        unless host_path.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/)
          errors.add(:host_path, "volumes must be named Docker volumes")
        end
      end
    end
end
