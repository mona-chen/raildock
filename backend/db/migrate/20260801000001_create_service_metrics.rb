class CreateServiceMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :service_metrics do |t|
      t.references :service, null: false, foreign_key: true
      t.float :cpu
      t.float :cpu_cores
      t.float :memory
      t.float :memory_used
      t.float :memory_limit
      t.float :network_in
      t.float :network_out
      t.datetime :sampled_at, null: false

      t.timestamps
    end

    add_index :service_metrics, [ :service_id, :sampled_at ]
  end
end
