class AddWebhookTokenToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :webhook_token, :string
    add_index :services, :webhook_token, unique: true
  end
end
