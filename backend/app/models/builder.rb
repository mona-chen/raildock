class Builder < ApplicationRecord
  belongs_to :plugin

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
  validates :dokku_builder, presence: true
  validates :status, presence: true, inclusion: { in: %w[built_in enabled disabled] }

  scope :built_in, -> { where(status: "built_in") }
  scope :enabled, -> { where(status: %w[built_in enabled]) }
  scope :for_source_type, ->(type) { where("source_types @> ?", [ type.to_s ].to_json) }

  def built_in?
    status == "built_in"
  end

  def enabled?
    built_in? || status == "enabled"
  end

  def supports_source?(type)
    Array(source_types).map(&:to_s).include?(type.to_s)
  end
end
