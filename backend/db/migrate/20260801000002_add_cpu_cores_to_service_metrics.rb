class AddCpuCoresToServiceMetrics < ActiveRecord::Migration[8.1]
  def change
    add_column :service_metrics, :cpu_cores, :float, if_not_exists: true
  end
end
