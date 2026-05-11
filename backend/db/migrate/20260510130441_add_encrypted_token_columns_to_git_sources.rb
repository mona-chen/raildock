class AddEncryptedTokenColumnsToGitSources < ActiveRecord::Migration[8.1]
  def change
    add_column :git_sources, :access_token_ciphertext, :text
    add_column :git_sources, :refresh_token_ciphertext, :text
  end
end
