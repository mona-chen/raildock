class AddTriggeredByToDeployments < ActiveRecord::Migration[8.1]
  def change
    add_column :deployments, :triggered_by, :string, default: "manual"
  end
end
