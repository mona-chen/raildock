class AddKindToStorageMounts < ActiveRecord::Migration[8.1]
  def up
    add_column :storage_mounts, :kind, :string

    # Backfill existing rows based on whether the host path is absolute.
    # Named Docker volumes are treated as "volume"; absolute host paths are "bind".
    execute <<~SQL
      UPDATE storage_mounts
      SET kind = CASE
        WHEN host_path LIKE '/%' THEN 'bind'
        ELSE 'volume'
      END
      WHERE kind IS NULL
    SQL

    change_column_default :storage_mounts, :kind, "volume"
    change_column_null :storage_mounts, :kind, false
  end

  def down
    remove_column :storage_mounts, :kind
  end
end
