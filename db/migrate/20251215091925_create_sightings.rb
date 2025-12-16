class CreateSightings < ActiveRecord::Migration[8.1]
  def change
    create_table :sightings do |t|
      t.string :icao, null: false
      t.string :callsign
      t.float :latitude
      t.float :longitude
      t.integer :altitude
      t.integer :speed
      t.integer :heading
      t.string :squawk
      t.float :signal_strength
      t.datetime :seen_at, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :sightings, :icao
    add_index :sightings, :seen_at
    add_index :sightings, [ :latitude, :longitude ]
  end
end
