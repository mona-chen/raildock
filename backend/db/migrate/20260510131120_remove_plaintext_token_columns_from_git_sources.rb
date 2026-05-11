class RemovePlaintextTokenColumnsFromGitSources < ActiveRecord::Migration[8.1]
  def change
    remove_column :git_sources, :access_token, :string if column_exists?(:git_sources, :access_token)
  end
end
