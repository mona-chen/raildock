class GitSource < ApplicationRecord
  validates :provider, inclusion: { in: %w[github gitlab bitbucket gitea] }

  def repos
    metadata&.[]("repos") || []
  end

  def repos=(value)
    self.metadata ||= {}
    self.metadata["repos"] = value
  end
end
