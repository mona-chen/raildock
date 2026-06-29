class OrganizationSshKey < ApplicationRecord
  belongs_to :organization

  validates :public_key, presence: true
  validates :fingerprint, presence: true
  validates :private_key_ciphertext, presence: true
  validates :organization_id, uniqueness: true

  LOCKBOX = Lockbox.new(key: Lockbox.master_key, encode: true)

  def private_key
    ciphertext = self[:private_key_ciphertext]
    return nil if ciphertext.blank?

    self.class::LOCKBOX.decrypt(ciphertext)
  rescue Lockbox::DecryptionError => e
    Rails.logger.error "Failed to decrypt organization SSH key #{id}: #{e.message}"
    nil
  end

  def private_key=(value)
    if value.present?
      self[:private_key_ciphertext] = self.class::LOCKBOX.encrypt(value)
    else
      self[:private_key_ciphertext] = nil
    end
  end
end
