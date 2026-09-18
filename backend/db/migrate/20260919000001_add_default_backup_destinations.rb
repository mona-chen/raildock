# frozen_string_literal: true

# Every backup destination picker in the UI was React state only: the service's
# own tab reset to "Local only" on every reload, and there was nowhere to say
# "this organization backs up off-site by default". These columns give the pick
# a home.
#
# `services.default_backup_destination_ids` is deliberately nullable: `nil` means
# the service has never chosen and inherits the organization default, while `[]`
# is a deliberate "local only" choice. A non-null default of `[]` would collapse
# those two cases and make "inherit" unrepresentable.
class AddDefaultBackupDestinations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :default_backup_destination_ids, :jsonb, null: false, default: [], if_not_exists: true
    add_column :services, :default_backup_destination_ids, :jsonb, if_not_exists: true
  end
end
