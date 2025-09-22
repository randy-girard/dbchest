class AddNotNullConstraintsToDatabaseReferences < ActiveRecord::Migration[8.0]
  def change
    # Add not null constraints after data has been populated
    change_column_null :clusters, :database_type_id, false
    change_column_null :nodes, :database_type_version_id, false
  end
end
