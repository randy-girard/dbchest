class AddDatabaseTypeToClusters < ActiveRecord::Migration[8.0]
  def change
    # First add the column as nullable
    add_reference :clusters, :database_type, null: true, foreign_key: true
  end
end
