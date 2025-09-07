class CreateProviderTypeNodeOptions < ActiveRecord::Migration[8.0]
  def change
    create_table :provider_type_node_options do |t|
      t.references :provider_type, null: false, foreign_key: true
      t.string :key
      t.string :label
      t.boolean :required, default: false

      t.timestamps
    end
  end
end
