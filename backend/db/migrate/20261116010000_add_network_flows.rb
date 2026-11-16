class AddNetworkFlows < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :network_flow_settings, :jsonb, null: false, default: {}
    add_column :servers, :network_flow_snapshot, :jsonb, null: false, default: {}
    create_table :network_flow_samples do |t|
      t.references :server, null: false, foreign_key: { on_delete: :cascade }
      t.references :service_link, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :sampled_at, null: false
      t.bigint :sent_bytes, null: false, default: 0
      t.bigint :received_bytes, null: false, default: 0
      t.integer :connections, null: false, default: 0
      t.float :window_seconds, null: false
    end
    add_index :network_flow_samples, [ :service_link_id, :sampled_at ], unique: true
    add_index :network_flow_samples, :sampled_at
  end
end
