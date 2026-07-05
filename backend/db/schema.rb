# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_03_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activity_events", force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", null: false
    t.string "message"
    t.jsonb "metadata"
    t.bigint "project_id", null: false
    t.string "service_name"
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_activity_events_on_project_id"
  end

  create_table "backup_copies", force: :cascade do |t|
    t.bigint "backup_destination_id"
    t.bigint "backup_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", default: "local", null: false
    t.jsonb "metadata", default: {}
    t.bigint "size", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.string "storage_key"
    t.datetime "updated_at", null: false
    t.index ["backup_destination_id"], name: "index_backup_copies_on_backup_destination_id"
    t.index ["backup_id", "backup_destination_id"], name: "index_backup_copies_on_backup_and_destination", unique: true, where: "(backup_destination_id IS NOT NULL)"
    t.index ["backup_id"], name: "index_backup_copies_on_backup_id"
  end

  create_table "backup_destinations", force: :cascade do |t|
    t.text "access_key_id_ciphertext"
    t.string "bucket", null: false
    t.datetime "created_at", null: false
    t.text "encryption_key_ciphertext"
    t.string "endpoint"
    t.text "last_error"
    t.datetime "last_verified_at"
    t.string "name", null: false
    t.bigint "organization_id"
    t.string "path_prefix"
    t.string "provider", default: "s3", null: false
    t.string "region", default: "auto", null: false
    t.text "secret_access_key_ciphertext"
    t.bigint "server_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_backup_destinations_on_organization_id_and_name", unique: true, where: "(organization_id IS NOT NULL)"
    t.index ["organization_id"], name: "index_backup_destinations_on_organization_id"
    t.index ["server_id", "name"], name: "index_backup_destinations_on_server_id_and_name", unique: true
    t.index ["server_id"], name: "index_backup_destinations_on_server_id"
  end

  create_table "backup_schedules", force: :cascade do |t|
    t.string "backup_kind", default: "database", null: false
    t.datetime "created_at", null: false
    t.string "frequency"
    t.datetime "last_run_at"
    t.jsonb "metadata", default: {}
    t.datetime "next_run_at"
    t.integer "retention_count"
    t.bigint "service_id", null: false
    t.bigint "storage_mount_id"
    t.datetime "updated_at", null: false
    t.index ["backup_kind"], name: "index_backup_schedules_on_backup_kind"
    t.index ["next_run_at"], name: "index_backup_schedules_on_next_run_at"
    t.index ["service_id"], name: "index_backup_schedules_on_service_id"
    t.index ["storage_mount_id"], name: "index_backup_schedules_on_storage_mount_id"
  end

  create_table "backups", force: :cascade do |t|
    t.bigint "backup_destination_id"
    t.string "backup_kind", default: "database", null: false
    t.datetime "created_at", null: false
    t.boolean "encrypted", default: false, null: false
    t.string "file_path"
    t.jsonb "metadata"
    t.bigint "service_id", null: false
    t.bigint "size"
    t.string "status"
    t.string "storage_key"
    t.datetime "updated_at", null: false
    t.index ["backup_destination_id"], name: "index_backups_on_backup_destination_id"
    t.index ["service_id"], name: "index_backups_on_service_id"
  end

  create_table "deploy_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "fingerprint"
    t.bigint "git_source_id"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.bigint "organization_id"
    t.text "private_key_ciphertext"
    t.text "public_key"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["fingerprint"], name: "index_deploy_keys_on_fingerprint"
    t.index ["git_source_id"], name: "index_deploy_keys_on_git_source_id"
    t.index ["organization_id", "name"], name: "index_deploy_keys_on_organization_id_and_name", unique: true, where: "(organization_id IS NOT NULL)"
    t.index ["organization_id"], name: "index_deploy_keys_on_organization_id"
    t.index ["user_id", "name"], name: "index_deploy_keys_on_user_id_and_name", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["user_id"], name: "index_deploy_keys_on_user_id"
  end

  create_table "deployments", force: :cascade do |t|
    t.string "branch"
    t.text "build_log"
    t.string "builder"
    t.string "commit_message"
    t.string "commit_sha"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "deploy_log"
    t.integer "event_sequence", default: 0, null: false
    t.string "idempotency_key"
    t.string "kind", default: "deploy", null: false
    t.bigint "service_id", null: false
    t.datetime "started_at"
    t.string "status"
    t.string "triggered_by", default: "manual"
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_deployments_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["kind"], name: "index_deployments_on_kind"
    t.index ["service_id", "kind", "created_at"], name: "index_deployments_on_service_id_and_kind_and_created_at"
    t.index ["service_id"], name: "index_deployments_on_service_id"
  end

  create_table "domains", force: :cascade do |t|
    t.string "challenge_type", default: "http", null: false
    t.datetime "created_at", null: false
    t.string "hostname"
    t.boolean "letsencrypt"
    t.integer "port"
    t.bigint "service_id", null: false
    t.boolean "ssl"
    t.datetime "ssl_checked_at"
    t.datetime "ssl_expires_at"
    t.string "ssl_status", default: "none", null: false
    t.string "ssl_status_message"
    t.integer "target_port", default: 80
    t.boolean "temporary", default: false, null: false
    t.datetime "updated_at", null: false
    t.boolean "wildcard", default: false
    t.index ["service_id"], name: "index_domains_on_service_id"
    t.index ["ssl_status"], name: "index_domains_on_ssl_status"
    t.index ["temporary"], name: "index_domains_on_temporary"
  end

  create_table "environment_variables", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_dokku_internal"
    t.string "key"
    t.bigint "service_id", null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["service_id"], name: "index_environment_variables_on_service_id"
  end

  create_table "git_sources", force: :cascade do |t|
    t.text "access_token_ciphertext"
    t.integer "account_type", default: 0
    t.integer "auth_method", default: 0
    t.boolean "connected"
    t.datetime "created_at", null: false
    t.string "installation_id"
    t.jsonb "metadata"
    t.bigint "organization_id"
    t.string "provider"
    t.text "refresh_token_ciphertext"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "username"
    t.index ["auth_method"], name: "index_git_sources_on_auth_method"
    t.index ["installation_id"], name: "index_git_sources_on_installation_id"
    t.index ["organization_id"], name: "index_git_sources_on_organization_id"
    t.index ["user_id"], name: "index_git_sources_on_user_id"
  end

  create_table "manifest_changes", force: :cascade do |t|
    t.string "change_type", null: false
    t.datetime "created_at", null: false
    t.string "field", null: false
    t.string "job_id"
    t.jsonb "new_value"
    t.jsonb "old_value"
    t.bigint "project_id", null: false
    t.string "service_name", null: false
    t.string "severity", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "service_name"], name: "index_manifest_changes_on_project_id_and_service_name"
    t.index ["project_id", "status"], name: "index_manifest_changes_on_project_id_and_status"
    t.index ["project_id"], name: "index_manifest_changes_on_project_id"
  end

  create_table "organization_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "invited_by_id", null: false
    t.bigint "organization_id", null: false
    t.string "role", default: "member", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["expires_at"], name: "index_organization_invitations_on_expires_at"
    t.index ["invited_by_id"], name: "index_organization_invitations_on_invited_by_id"
    t.index ["organization_id", "email"], name: "index_organization_invitations_on_organization_id_and_email"
    t.index ["organization_id"], name: "index_organization_invitations_on_organization_id"
    t.index ["token"], name: "index_organization_invitations_on_token", unique: true
    t.index ["user_id"], name: "index_organization_invitations_on_user_id"
  end

  create_table "organization_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["organization_id"], name: "index_organization_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_organization_memberships_on_user_id_and_organization_id", unique: true
    t.index ["user_id"], name: "index_organization_memberships_on_user_id"
  end

  create_table "organization_ssh_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.bigint "organization_id", null: false
    t.text "private_key_ciphertext", null: false
    t.text "public_key", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_organization_ssh_keys_on_organization_id", unique: true
  end

  create_table "organizations", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_organizations_on_owner_id"
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "plugins", force: :cascade do |t|
    t.string "category", null: false
    t.jsonb "config_schema", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "built_in", null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["category"], name: "index_plugins_on_category"
    t.index ["slug"], name: "index_plugins_on_slug", unique: true
    t.index ["status"], name: "index_plugins_on_status"
  end

  create_table "postgres_pitr_configs", force: :cascade do |t|
    t.bigint "backup_destination_id", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "last_base_backup_at"
    t.text "last_error"
    t.datetime "last_wal_archived_at"
    t.integer "retention_days", default: 7, null: false
    t.bigint "service_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_destination_id"], name: "index_postgres_pitr_configs_on_backup_destination_id"
    t.index ["service_id"], name: "index_postgres_pitr_configs_on_service_id", unique: true
  end

  create_table "process_types", force: :cascade do |t|
    t.string "command"
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "quantity"
    t.integer "running"
    t.bigint "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_process_types_on_service_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "environment"
    t.text "manifest_content"
    t.boolean "manifest_drift_detected", default: false, null: false
    t.string "manifest_format"
    t.datetime "manifest_last_applied_at"
    t.datetime "manifest_last_synced_at"
    t.string "name"
    t.string "network_name"
    t.bigint "organization_id"
    t.bigint "server_id"
    t.jsonb "shared_vars", default: []
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["organization_id"], name: "index_projects_on_organization_id"
    t.index ["server_id"], name: "index_projects_on_server_id"
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "restore_drills", force: :cascade do |t|
    t.bigint "backup_id", null: false
    t.boolean "checksum_verified", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "isolated_resource_name"
    t.text "log"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_id", "created_at"], name: "index_restore_drills_on_backup_id_and_created_at"
    t.index ["backup_id"], name: "index_restore_drills_on_backup_id"
  end

  create_table "servers", force: :cascade do |t|
    t.boolean "auto_domains", default: true, null: false
    t.string "base_domain", default: "sslip.io"
    t.datetime "created_at", null: false
    t.string "default_proxy"
    t.integer "disk_total"
    t.integer "disk_used"
    t.text "dns_challenge_credentials_ciphertext"
    t.string "dns_challenge_provider"
    t.string "docker_version"
    t.string "dokku_version"
    t.string "external_proxy_cert_resolver"
    t.jsonb "external_proxy_default_labels", default: {}, null: false
    t.string "external_proxy_http_entrypoint", default: "web", null: false
    t.string "external_proxy_https_entrypoint", default: "websecure", null: false
    t.string "external_proxy_network"
    t.string "external_proxy_redirect_middleware"
    t.string "host"
    t.text "host_key"
    t.string "host_key_fingerprint"
    t.integer "memory_total"
    t.integer "memory_used"
    t.string "name"
    t.bigint "organization_id"
    t.string "os"
    t.string "proxy_mode", default: "managed", null: false
    t.string "public_ip"
    t.text "ssh_key_ciphertext"
    t.string "ssh_user", default: "dokku"
    t.string "status"
    t.datetime "updated_at", null: false
    t.string "uptime"
    t.bigint "user_id"
    t.index ["organization_id"], name: "index_servers_on_organization_id"
    t.index ["user_id"], name: "index_servers_on_user_id"
  end

  create_table "service_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "from_service_id", null: false
    t.bigint "to_service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["from_service_id", "to_service_id"], name: "index_service_links_on_from_service_id_and_to_service_id", unique: true
    t.index ["from_service_id"], name: "index_service_links_on_from_service_id"
    t.index ["to_service_id"], name: "index_service_links_on_to_service_id"
  end

  create_table "service_subtypes", force: :cascade do |t|
    t.jsonb "capabilities", default: []
    t.string "color"
    t.string "command_namespace"
    t.jsonb "config_schema", default: {}
    t.datetime "created_at", null: false
    t.string "default_version"
    t.text "description"
    t.string "dokku_plugin"
    t.string "env_var_prefix"
    t.string "icon"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.bigint "plugin_id", null: false
    t.string "service_type", null: false
    t.string "subtype", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_service_subtypes_on_capabilities", using: :gin
    t.index ["plugin_id", "subtype"], name: "index_service_subtypes_on_plugin_id_and_subtype", unique: true
    t.index ["plugin_id"], name: "index_service_subtypes_on_plugin_id"
    t.index ["service_type"], name: "index_service_subtypes_on_service_type"
    t.index ["subtype"], name: "index_service_subtypes_on_subtype", unique: true
  end

  create_table "services", force: :cascade do |t|
    t.boolean "auto_deploy", default: true, null: false
    t.string "branch"
    t.string "builder"
    t.integer "canvas_x"
    t.integer "canvas_y"
    t.jsonb "config", default: {}
    t.jsonb "config_overrides", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "detected_port"
    t.string "docker_image"
    t.string "dokku_app_name"
    t.boolean "exposed"
    t.string "git_repo"
    t.string "internal_hostname"
    t.string "last_deployed"
    t.boolean "locked"
    t.boolean "maintenance_mode", default: false, null: false
    t.string "managed_by", default: "ui", null: false
    t.string "name"
    t.integer "port"
    t.bigint "project_id", null: false
    t.integer "restart_max_retries"
    t.string "restart_policy"
    t.string "root_directory"
    t.string "service_type"
    t.string "start_command"
    t.string "status"
    t.string "subtype"
    t.datetime "updated_at", null: false
    t.string "version"
    t.string "webhook_token"
    t.index ["managed_by"], name: "index_services_on_managed_by"
    t.index ["project_id"], name: "index_services_on_project_id"
    t.index ["webhook_token"], name: "index_services_on_webhook_token", unique: true
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "storage_mounts", force: :cascade do |t|
    t.string "container_path"
    t.datetime "created_at", null: false
    t.string "host_path"
    t.string "kind", null: false
    t.bigint "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_storage_mounts_on_service_id"
  end

  create_table "system_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_value_ciphertext"
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_system_settings_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "activity_events", "projects"
  add_foreign_key "backup_copies", "backup_destinations"
  add_foreign_key "backup_copies", "backups"
  add_foreign_key "backup_destinations", "organizations"
  add_foreign_key "backup_destinations", "servers"
  add_foreign_key "backup_schedules", "services"
  add_foreign_key "backup_schedules", "storage_mounts"
  add_foreign_key "backups", "backup_destinations"
  add_foreign_key "backups", "services"
  add_foreign_key "deploy_keys", "git_sources"
  add_foreign_key "deploy_keys", "organizations"
  add_foreign_key "deploy_keys", "users"
  add_foreign_key "deployments", "services"
  add_foreign_key "domains", "services"
  add_foreign_key "environment_variables", "services"
  add_foreign_key "git_sources", "organizations"
  add_foreign_key "git_sources", "users"
  add_foreign_key "manifest_changes", "projects"
  add_foreign_key "organization_invitations", "organizations"
  add_foreign_key "organization_invitations", "users"
  add_foreign_key "organization_invitations", "users", column: "invited_by_id"
  add_foreign_key "organization_memberships", "organizations"
  add_foreign_key "organization_memberships", "users"
  add_foreign_key "organization_ssh_keys", "organizations"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "postgres_pitr_configs", "backup_destinations"
  add_foreign_key "postgres_pitr_configs", "services"
  add_foreign_key "process_types", "services"
  add_foreign_key "projects", "organizations"
  add_foreign_key "projects", "servers"
  add_foreign_key "projects", "users"
  add_foreign_key "restore_drills", "backups"
  add_foreign_key "servers", "organizations"
  add_foreign_key "servers", "users"
  add_foreign_key "service_links", "services", column: "from_service_id"
  add_foreign_key "service_links", "services", column: "to_service_id"
  add_foreign_key "service_subtypes", "plugins"
  add_foreign_key "services", "projects"
  add_foreign_key "storage_mounts", "services"
end
