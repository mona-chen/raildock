class AddOrganizationToProjectsAndGitSources < ActiveRecord::Migration[8.1]
  def change
    # Add organization scoping to projects
    add_reference :projects, :organization, foreign_key: true

    # Add organization/user scoping to git_sources
    # Git sources belong to EITHER an org OR a user (not both)
    add_reference :git_sources, :organization, foreign_key: true
    add_reference :git_sources, :user, foreign_key: true
  end
end
