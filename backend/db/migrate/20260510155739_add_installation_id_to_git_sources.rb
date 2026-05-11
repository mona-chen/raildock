class AddInstallationIdToGitSources < ActiveRecord::Migration[8.1]
  def change
    add_column :git_sources, :installation_id, :string
    add_index :git_sources, :installation_id
  end
end
