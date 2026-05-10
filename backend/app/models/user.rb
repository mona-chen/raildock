class User < ApplicationRecord
  has_secure_password

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  def generate_jwt
    JWT.encode({ user_id: id, exp: 30.days.from_now.to_i }, Rails.application.credentials.secret_key_base)
  end
end
