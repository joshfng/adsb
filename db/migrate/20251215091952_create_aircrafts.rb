class CreateAircrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :aircraft, id: false do |t|
      t.string :icao, primary_key: true
      t.string :callsign
      t.datetime :first_seen
      t.datetime :last_seen
      t.integer :sighting_count, default: 1
    end
    add_index :aircraft, :last_seen
  end
end
