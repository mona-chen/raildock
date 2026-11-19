class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :project, foreign_key: true
      t.references :environment, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :prefix, null: false
      t.jsonb :scopes, null: false, default: []
      t.datetime :expires_at
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.string :client_id
      t.string :audience
      t.timestamps
    end
    add_index :api_tokens, :token_digest, unique: true
    add_index :api_tokens, :prefix
  end
end
