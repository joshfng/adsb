# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_12_16_003258) do
  create_table "aircraft", primary_key: "icao", id: :string, force: :cascade do |t|
    t.string "callsign"
    t.datetime "first_seen"
    t.datetime "last_seen"
    t.integer "sighting_count", default: 1
    t.index ["last_seen"], name: "index_aircraft_on_last_seen"
  end

  create_table "aircraft_types", primary_key: "code", id: :string, force: :cascade do |t|
    t.string "aircraft_type"
    t.string "engine_type"
    t.string "manufacturer"
    t.string "model"
    t.integer "num_engines"
    t.integer "num_seats"
    t.integer "speed"
    t.string "weight_class"
  end

  create_table "registrations", primary_key: "icao_hex", id: :string, force: :cascade do |t|
    t.string "aircraft_type_code"
    t.string "city"
    t.string "engine_type_code"
    t.string "mfr_mdl_code"
    t.string "n_number"
    t.string "owner"
    t.string "serial_number"
    t.string "state"
    t.integer "year"
    t.index ["n_number"], name: "index_registrations_on_n_number"
  end

  create_table "sightings", force: :cascade do |t|
    t.integer "altitude"
    t.string "callsign"
    t.integer "heading"
    t.string "icao", null: false
    t.float "latitude"
    t.float "longitude"
    t.datetime "seen_at", default: -> { "CURRENT_TIMESTAMP" }
    t.float "signal_strength"
    t.integer "speed"
    t.string "squawk"
    t.index ["icao", "seen_at"], name: "index_sightings_on_icao_and_seen_at"
    t.index ["icao"], name: "index_sightings_on_icao"
    t.index ["latitude", "longitude"], name: "index_sightings_on_latitude_and_longitude"
    t.index ["seen_at", "latitude", "longitude"], name: "index_sightings_on_seen_at_and_position", where: "latitude IS NOT NULL AND longitude IS NOT NULL"
    t.index ["seen_at"], name: "index_sightings_on_seen_at"
  end
end
