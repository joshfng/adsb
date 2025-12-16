class AddIndexesToSightings < ActiveRecord::Migration[8.1]
  def change
    # Compound index for time-based queries filtered by aircraft
    add_index :sightings, [:icao, :seen_at], name: "index_sightings_on_icao_and_seen_at"

    # Compound index for heatmap/position queries within time range
    add_index :sightings, [:seen_at, :latitude, :longitude],
              name: "index_sightings_on_seen_at_and_position",
              where: "latitude IS NOT NULL AND longitude IS NOT NULL"
  end
end
