class AddBranchToDeployments < ActiveRecord::Migration[8.1]
  def change
    add_column :deployments, :branch, :string
  end
end
