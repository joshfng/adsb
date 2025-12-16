class CreateRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :registrations, id: false do |t|
      t.string :icao_hex, primary_key: true
      t.string :n_number
      t.string :serial_number
      t.string :mfr_mdl_code
      t.integer :year
      t.string :owner
      t.string :city
      t.string :state
      t.string :aircraft_type_code
      t.string :engine_type_code
    end
    add_index :registrations, :n_number
  end
end
