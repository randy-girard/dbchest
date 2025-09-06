class CreateProviderSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :provider_settings do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :provider_type_option, null: false, foreign_key: true
      t.string :key
      t.string :value

      t.timestamps
    end
  end
end
