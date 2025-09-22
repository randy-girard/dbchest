class CreateDatabaseTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :database_types do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :database_types, :name, unique: true
    add_index :database_types, :slug, unique: true
  end
end
