class AddHttpHourlyRollups < ActiveRecord::Migration[8.1]
  def change
    add_column :http_traffic_buckets, :resolution, :string, null: false, default: "minute"
    remove_index :http_traffic_buckets, [ :server_id, :bucket_at ]
    add_index :http_traffic_buckets, [ :server_id, :resolution, :bucket_at ], unique: true
  end
end
