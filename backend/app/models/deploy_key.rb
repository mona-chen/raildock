class DeployKey < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :user, optional: true
  belongs_to :git_source, optional: true

  has_encrypted :private_key

  validates :name, presence: true
  validates :public_key, presence: true
  validates :fingerprint, presence: true, uniqueness: true
  validate :must_belong_to_org_or_user

  def owner
    organization || user
  end

  def touch_last_used!
    update!(last_used_at: Time.current)
  end

  private

  def must_belong_to_org_or_user
    if organization_id.blank? && user_id.blank?
      errors.add(:base, 'Must belong to an organization or a user')
    elsif organization_id.present? && user_id.present?
      errors.add(:base, 'Cannot belong to both an organization and a user')
    end
  end
end
