class Plugin < ApplicationRecord
  has_many :service_subtypes, dependent: :destroy

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
  validates :category, presence: true, inclusion: { in: %w[database cache queue search service tool] }
  validates :status, presence: true, inclusion: { in: %w[built_in enabled disabled] }

  scope :built_in, -> { where(status: "built_in") }
  scope :enabled, -> { where(status: %w[built_in enabled]) }

  def built_in?
    status == "built_in"
  end

  def enabled?
    built_in? || status == "enabled"
  end
end
