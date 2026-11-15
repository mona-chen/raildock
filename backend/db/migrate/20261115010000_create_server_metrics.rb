class CreateServerMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :server_metrics do |t|
      t.references :server, null: false, foreign_key: true
      t.datetime :sampled_at, null: false
      t.jsonb :data, null: false, default: {}
    end
    add_index :server_metrics, [ :server_id, :sampled_at ]
    add_index :server_metrics, :sampled_at
  end
end
