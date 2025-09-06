class CreateProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :providers do |t|
      t.references :provider_type, null: false, foreign_key: true
      t.string :name
      t.timestamps
    end
  end
end
