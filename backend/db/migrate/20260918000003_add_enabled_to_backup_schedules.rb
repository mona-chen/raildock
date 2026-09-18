# frozen_string_literal: true

# Coolify and Dokploy both let a backup schedule be paused without deleting it
# (and without losing its next-run bookkeeping). RailDock had no such switch, so
# the only way to stop a schedule was to delete and recreate it.
class AddEnabledToBackupSchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :backup_schedules, :enabled, :boolean, null: false, default: true, if_not_exists: true
  end
end
