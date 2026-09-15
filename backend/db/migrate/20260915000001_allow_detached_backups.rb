# frozen_string_literal: true

# Backup artifacts must outlive the service they came from.
#
# `services` cascades to `backups` on destroy, which used to delete the only
# record pointing at a restorable artifact — including the snapshot RailDock now
# takes immediately before a destructive operation. Making `service_id`
# nullable (with `dependent: :nullify`) keeps the artifact and its source
# metadata available for recovery after the service row is gone.
class AllowDetachedBackups < ActiveRecord::Migration[7.2]
  def change
    change_column_null :backups, :service_id, true
  end
end
