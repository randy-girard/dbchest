class AddDatabaseTypeVersionToNodes < ActiveRecord::Migration[8.0]
  def change
    # First add the column as nullable
    add_reference :nodes, :database_type_version, null: true, foreign_key: true
  end
end
