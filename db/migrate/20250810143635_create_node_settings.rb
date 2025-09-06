class CreateNodeSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :node_settings do |t|
      t.references :node, null: false, foreign_key: true
      t.references :provider_type_node_option, null: false, foreign_key: true
      t.string :key
      t.string :value

      t.timestamps
    end
  end
end
