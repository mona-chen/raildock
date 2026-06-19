class AddKindToDeployments < ActiveRecord::Migration[8.0]
  def change
    add_column :deployments, :kind, :string, default: "deploy", null: false
    add_index :deployments, :kind
    add_index :deployments, [ :service_id, :kind, :created_at ]
  end
end
