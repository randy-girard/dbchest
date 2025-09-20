class AddStatusToNodes < ActiveRecord::Migration[8.0]
  def change
    add_column :nodes, :status, :string, default: 'pending'
  end
end
