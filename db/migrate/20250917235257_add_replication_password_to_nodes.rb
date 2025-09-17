class AddReplicationPasswordToNodes < ActiveRecord::Migration[8.0]
  def change
    add_column :nodes, :replication_password, :string
  end
end
