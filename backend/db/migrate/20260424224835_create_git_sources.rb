class CreateGitSources < ActiveRecord::Migration[8.1]
  def change
    create_table :git_sources do |t|
      t.string :provider
      t.boolean :connected
      t.string :username
      t.string :access_token
      t.jsonb :metadata

      t.timestamps
    end
  end
end
