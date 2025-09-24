class AddRootPasswordToNodes < ActiveRecord::Migration[8.0]
  def change
    add_column :nodes, :root_password, :string
  end
end
