class AddProjectDeletionStatus < ActiveRecord::Migration[8.0]
  def change
    add_column :projects, :deletion_status, :string
    add_column :projects, :deletion_error, :text
    add_column :projects, :deletion_error_code, :string
    add_column :projects, :deletion_requested_at, :datetime
  end
end
