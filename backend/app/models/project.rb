class Project < ApplicationRecord
  belongs_to :server, optional: true
  has_many :services, dependent: :destroy
  has_many :activity_events, dependent: :destroy

  validates :name, presence: true
  validates :environment, inclusion: { in: %w[production staging development] }

  before_validation :set_default_environment, on: :create

  def set_default_environment
    self.environment ||= 'production'
  end

  def service_ids
    services.pluck(:id)
  end

  def shared_vars
    read_attribute(:shared_vars) || []
  end

  def as_json(options = {})
    super(options.merge(
      methods: [:service_ids, :shared_vars]
    ))
  end
end
