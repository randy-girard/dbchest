class CreateCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :credentials do |t|
      t.references :node, null: false, foreign_key: true
      t.string :username
      t.string :password

      t.timestamps
    end
  end
end
