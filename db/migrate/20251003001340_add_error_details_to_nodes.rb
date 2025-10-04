class AddErrorDetailsToNodes < ActiveRecord::Migration[8.0]
  def change
    add_column :nodes, :error_details, :text
  end
end
