class CreateDatabaseTypeVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :database_type_versions do |t|
      t.references :database_type, null: false, foreign_key: true
      t.string :version, null: false
      t.text :install_command, null: false
      t.text :config_template
      t.integer :default_port, null: false
      t.string :service_name, null: false
      t.string :data_directory_pattern
      t.string :config_file_pattern
      t.boolean :is_default, default: false

      t.timestamps
    end

    add_index :database_type_versions, [:database_type_id, :version], unique: true, name: 'index_db_type_versions_on_type_and_version'
    add_index :database_type_versions, :is_default
  end
end
