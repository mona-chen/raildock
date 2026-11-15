class AddHttpObservability < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :traffic_settings, :jsonb, null: false, default: {}
    add_column :servers, :traffic_cursor, :jsonb, null: false, default: {}
    add_column :organizations, :notification_settings, :jsonb, null: false, default: {}
    create_table :http_traffic_buckets do |t|
      t.references :server, null: false, foreign_key: true
      t.datetime :bucket_at, null: false
      t.jsonb :data, null: false, default: {}
    end
    add_index :http_traffic_buckets, [ :server_id, :bucket_at ], unique: true
    add_index :http_traffic_buckets, :bucket_at
    create_table :monitoring_incidents do |t|
      t.references :server, null: false, foreign_key: true
      t.string :signal, null: false
      t.string :state, null: false, default: "pending"
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :resolved_at
      t.string :message, null: false
      t.string :delivery_status, null: false, default: "disabled"
      t.datetime :notified_at
      t.timestamps
    end
    add_index :monitoring_incidents, [ :server_id, :signal ], unique: true, where: "resolved_at IS NULL", name: "index_active_monitoring_incident"
  end
end
