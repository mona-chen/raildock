class BackupDestination < ApplicationRecord
  belongs_to :server, optional: true
  belongs_to :organization, optional: true
  has_many :backups, dependent: :restrict_with_error
  has_many :backup_copies, dependent: :restrict_with_error
  has_many :postgres_pitr_configs, dependent: :restrict_with_error

  has_encrypted :access_key_id
  has_encrypted :secret_access_key
  has_encrypted :encryption_key

  enum :status, { pending: "pending", verified: "verified", failed: "failed" }

  validates :name, :bucket, :region, presence: true
  validates :provider, inclusion: { in: %w[s3 r2] }
  validates :name, uniqueness: { scope: :server_id }, if: -> { server_id.present? }
  validates :name, uniqueness: { scope: :organization_id }, if: -> { organization_id.present? }
  validates :encryption_key, format: { with: /\A[0-9a-f]{64}\z/i, message: "must be a 64-character hexadecimal recovery key" }
  validate :belongs_to_a_scope

  before_validation :ensure_encryption_key, on: :create

  def object_key(*parts)
    ([ path_prefix.presence, *parts ].compact.join("/")).gsub(%r{/+}, "/").delete_prefix("/")
  end

  def as_json(options = {})
    super(options.merge(except: %i[ access_key_id_ciphertext secret_access_key_ciphertext encryption_key_ciphertext ])).merge(
      "configured" => access_key_id.present? && secret_access_key.present? && encryption_key.present?
    )
  end

  private
    def ensure_encryption_key
      self.encryption_key ||= SecureRandom.hex(32)
    end

    def belongs_to_a_scope
      return if server_id.present? || organization_id.present?

      errors.add(:base, "must belong to a server or organization")
    end
end
