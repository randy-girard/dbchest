class CreateProviderTypeOptions < ActiveRecord::Migration[8.0]
  def change
    create_table :provider_type_options do |t|
      t.references :provider_type, null: false, foreign_key: true
      t.string :key
      t.string :label
      t.boolean :required
      t.boolean :sensitive

      t.timestamps
    end
  end
end
