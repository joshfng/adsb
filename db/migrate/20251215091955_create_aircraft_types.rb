class CreateAircraftTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :aircraft_types, id: false do |t|
      t.string :code, primary_key: true
      t.string :manufacturer
      t.string :model
      t.string :aircraft_type
      t.string :engine_type
      t.integer :num_engines
      t.integer :num_seats
      t.string :weight_class
      t.integer :speed
    end
  end
end
