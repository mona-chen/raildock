class RemoveDefaultKindFromStorageMounts < ActiveRecord::Migration[8.1]
  def up
    change_column_default :storage_mounts, :kind, nil
  end

  def down
    change_column_default :storage_mounts, :kind, "volume"
  end
end
