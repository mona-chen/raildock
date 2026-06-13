class AddIdempotencyKeyToDeployments < ActiveRecord::Migration[8.0]
  def change
    add_column :deployments, :idempotency_key, :string
    add_index :deployments, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
  end
end
