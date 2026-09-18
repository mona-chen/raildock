# frozen_string_literal: true

# Container disk throughput, sampled next to CPU and memory so the metrics
# graphs can show I/O in addition to network traffic. Values are cumulative
# bytes reported by `docker stats`; the UI derives a rate between samples.
class AddBlockIoToServiceMetrics < ActiveRecord::Migration[8.1]
  def change
    add_column :service_metrics, :block_read, :float, if_not_exists: true
    add_column :service_metrics, :block_write, :float, if_not_exists: true
  end
end
