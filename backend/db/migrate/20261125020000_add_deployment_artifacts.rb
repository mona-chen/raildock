class AddDeploymentArtifacts < ActiveRecord::Migration[8.1]
  def change
    add_column :deployments, :artifact_image_id, :string
    add_column :deployments, :artifact_image_ref, :string
    add_column :deployments, :config_revision, :string
    add_column :deployments, :native_build_id, :string
    add_column :deployments, :rollback_source_id, :bigint
  end
end
