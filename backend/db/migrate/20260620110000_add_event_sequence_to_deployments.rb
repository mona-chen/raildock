class AddEventSequenceToDeployments < ActiveRecord::Migration[8.1]
  def change
    add_column :deployments, :event_sequence, :integer, null: false, default: 0
  end
end
