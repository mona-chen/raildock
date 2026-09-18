# A named, switchable grouping of a project's services.
#
# Railway, Coolify and Dokploy all behave the same way, and RailDock follows
# them: a project always has exactly one default environment (`production`),
# additional environments are created explicitly, and the default can never be
# deleted. Deleting an environment that still owns services is refused so a
# switcher can never silently orphan a running app.
class Environment < ApplicationRecord
  belongs_to :project
  has_many :services, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 40 }
  validates :slug, presence: true, format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :slug, uniqueness: { scope: :project_id }
  validate :only_one_default_per_project, if: :is_default?

  before_validation :assign_slug, if: -> { slug.blank? || name_changed? }
  # `prepend` so the guard runs before `dependent: :restrict_with_error`.
  before_destroy :prevent_guarded_destroy, prepend: true

  # The default environment always leads the switcher, then the rest in the
  # order they were created — the same ordering Railway and Dokploy present.
  scope :ordered, -> { order(is_default: :desc, created_at: :asc, id: :asc) }

  def self.slugify(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  def default?
    is_default?
  end

  def service_ids
    services.pluck(:id)
  end

  def service_count
    services.count
  end

  # Serialized shape the canvas and the environment switcher consume.
  def as_json(options = {})
    super(options.merge(methods: [ :service_ids, :service_count ]))
  end

  private
    def assign_slug
      self.slug = self.class.slugify(name)
    end

    def only_one_default_per_project
      scope = project&.environments&.where(is_default: true)
      scope = scope.where.not(id: id) if persisted?
      return unless scope&.exists?

      errors.add(:is_default, "is already set on another environment")
    end

    def prevent_guarded_destroy
      if is_default?
        errors.add(:base, "#{name} is the default environment and cannot be deleted")
        throw :abort
      end

      return unless services.exists?

      errors.add(:base, "Move the #{services.count} service(s) in #{name} to another environment before deleting it")
      throw :abort
    end
end
