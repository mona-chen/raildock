class AddAuthMethodAndAccountTypeToGitSources < ActiveRecord::Migration[8.1]
  def change
    add_column :git_sources, :auth_method, :integer, default: 0
    add_column :git_sources, :account_type, :integer, default: 0
    add_index :git_sources, :auth_method
  end
end
