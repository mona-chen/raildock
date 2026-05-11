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

ActiveRecord::Schema[8.1].define(version: 2026_05_11_045012) do
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

  create_table "backup_schedules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "frequency"
    t.datetime "last_run_at"
    t.datetime "next_run_at"
    t.integer "retention_count"
    t.bigint "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_backup_schedules_on_service_id"
  end

  create_table "backups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_path"
    t.jsonb "metadata"
    t.bigint "service_id", null: false
    t.integer "size"
    t.string "status"
    t.datetime "updated_at", null: false
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
    t.bigint "service_id", null: false
    t.datetime "started_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_deployments_on_service_id"
  end

  create_table "domains", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.boolean "letsencrypt"
    t.integer "port"
    t.bigint "service_id", null: false
    t.boolean "ssl"
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_domains_on_service_id"
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
    t.string "name"
    t.bigint "organization_id"
    t.bigint "server_id"
    t.jsonb "shared_vars", default: []
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_projects_on_organization_id"
    t.index ["server_id"], name: "index_projects_on_server_id"
  end

  create_table "servers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_proxy"
    t.integer "disk_total"
    t.integer "disk_used"
    t.string "docker_version"
    t.string "dokku_version"
    t.string "host"
    t.integer "memory_total"
    t.integer "memory_used"
    t.string "name"
    t.string "os"
    t.text "ssh_key_ciphertext"
    t.string "status"
    t.datetime "updated_at", null: false
    t.string "uptime"
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

  create_table "services", force: :cascade do |t|
    t.string "branch"
    t.string "builder"
    t.jsonb "config", default: {}
    t.datetime "created_at", null: false
    t.string "docker_image"
    t.string "dokku_app_name"
    t.boolean "exposed"
    t.string "git_repo"
    t.string "last_deployed"
    t.boolean "locked"
    t.string "name"
    t.integer "port"
    t.bigint "project_id", null: false
    t.integer "restart_max_retries"
    t.string "restart_policy"
    t.string "service_type"
    t.string "status"
    t.string "subtype"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["project_id"], name: "index_services_on_project_id"
  end

  create_table "storage_mounts", force: :cascade do |t|
    t.string "container_path"
    t.datetime "created_at", null: false
    t.string "host_path"
    t.bigint "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_storage_mounts_on_service_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.string "password_digest"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "activity_events", "projects"
  add_foreign_key "backup_schedules", "services"
  add_foreign_key "backups", "services"
  add_foreign_key "deploy_keys", "git_sources"
  add_foreign_key "deploy_keys", "organizations"
  add_foreign_key "deploy_keys", "users"
  add_foreign_key "deployments", "services"
  add_foreign_key "domains", "services"
  add_foreign_key "environment_variables", "services"
  add_foreign_key "git_sources", "organizations"
  add_foreign_key "git_sources", "users"
  add_foreign_key "organization_memberships", "organizations"
  add_foreign_key "organization_memberships", "users"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "process_types", "services"
  add_foreign_key "projects", "organizations"
  add_foreign_key "projects", "servers"
  add_foreign_key "service_links", "services", column: "from_service_id"
  add_foreign_key "service_links", "services", column: "to_service_id"
  add_foreign_key "services", "projects"
  add_foreign_key "storage_mounts", "services"
end
