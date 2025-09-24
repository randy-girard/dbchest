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

ActiveRecord::Schema[8.0].define(version: 2025_09_22_182244) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "clusters", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "database_type_id", null: false
    t.index ["database_type_id"], name: "index_clusters_on_database_type_id"
  end

  create_table "credentials", force: :cascade do |t|
    t.bigint "node_id", null: false
    t.string "username"
    t.string "password"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["node_id"], name: "index_credentials_on_node_id"
  end

  create_table "database_type_versions", force: :cascade do |t|
    t.bigint "database_type_id", null: false
    t.string "version", null: false
    t.text "install_command", null: false
    t.text "config_template"
    t.integer "default_port", null: false
    t.string "service_name", null: false
    t.string "data_directory_pattern"
    t.string "config_file_pattern"
    t.boolean "is_default", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["database_type_id", "version"], name: "index_db_type_versions_on_type_and_version", unique: true
    t.index ["database_type_id"], name: "index_database_type_versions_on_database_type_id"
    t.index ["is_default"], name: "index_database_type_versions_on_is_default"
  end

  create_table "database_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_database_types_on_name", unique: true
    t.index ["slug"], name: "index_database_types_on_slug", unique: true
  end

  create_table "node_settings", force: :cascade do |t|
    t.bigint "node_id", null: false
    t.bigint "provider_type_node_option_id", null: false
    t.string "key"
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["node_id"], name: "index_node_settings_on_node_id"
    t.index ["provider_type_node_option_id"], name: "index_node_settings_on_provider_type_node_option_id"
  end

  create_table "nodes", force: :cascade do |t|
    t.bigint "cluster_id", null: false
    t.bigint "provider_id", null: false
    t.string "name"
    t.jsonb "terraform_state", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "runtime_config", default: {}
    t.string "ssh_private_key"
    t.string "ssh_public_key"
    t.bigint "parent_node_id"
    t.string "replication_password"
    t.string "status", default: "pending"
    t.bigint "database_type_version_id", null: false
    t.string "root_password"
    t.index ["cluster_id"], name: "index_nodes_on_cluster_id"
    t.index ["database_type_version_id"], name: "index_nodes_on_database_type_version_id"
    t.index ["parent_node_id"], name: "index_nodes_on_parent_node_id"
    t.index ["provider_id"], name: "index_nodes_on_provider_id"
    t.index ["status"], name: "index_nodes_on_status"
  end

  create_table "provider_settings", force: :cascade do |t|
    t.bigint "provider_id", null: false
    t.bigint "provider_type_option_id", null: false
    t.string "key"
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_id"], name: "index_provider_settings_on_provider_id"
    t.index ["provider_type_option_id"], name: "index_provider_settings_on_provider_type_option_id"
  end

  create_table "provider_type_node_options", force: :cascade do |t|
    t.bigint "provider_type_id", null: false
    t.string "key"
    t.string "label"
    t.boolean "required", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_type_id"], name: "index_provider_type_node_options_on_provider_type_id"
  end

  create_table "provider_type_options", force: :cascade do |t|
    t.bigint "provider_type_id", null: false
    t.string "key"
    t.string "label"
    t.boolean "required"
    t.boolean "sensitive"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_type_id"], name: "index_provider_type_options_on_provider_type_id"
  end

  create_table "provider_types", force: :cascade do |t|
    t.string "name"
    t.string "key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "providers", force: :cascade do |t|
    t.bigint "provider_type_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_type_id"], name: "index_providers_on_provider_type_id"
  end

  add_foreign_key "clusters", "database_types"
  add_foreign_key "credentials", "nodes"
  add_foreign_key "database_type_versions", "database_types"
  add_foreign_key "node_settings", "nodes"
  add_foreign_key "node_settings", "provider_type_node_options"
  add_foreign_key "nodes", "clusters"
  add_foreign_key "nodes", "database_type_versions"
  add_foreign_key "nodes", "nodes", column: "parent_node_id"
  add_foreign_key "nodes", "providers"
  add_foreign_key "provider_settings", "provider_type_options"
  add_foreign_key "provider_settings", "providers"
  add_foreign_key "provider_type_node_options", "provider_types"
  add_foreign_key "provider_type_options", "provider_types"
  add_foreign_key "providers", "provider_types"
end
