# frozen_string_literal: true

require_relative "logging"

# FAA Aircraft Database Lookup using ActiveRecord
class FAALookup
  def initialize
    # No mutex needed - ActiveRecord handles thread safety
  end

  def lookup(icao_hex)
    icao = icao_hex.to_s.upcase.strip
    return nil if icao.empty?

    # Query registration with eager loading of aircraft_type
    reg = Registration.includes(:aircraft_type).find_by(icao_hex: icao)
    return nil unless reg

    aircraft_type = reg.aircraft_type

    {
      n_number: reg.n_number,
      serial_number: reg.serial_number,
      mfr_mdl_code: reg.mfr_mdl_code,
      year: reg.year,
      owner: reg.owner,
      city: reg.city,
      state: reg.state,
      aircraft_type_code: reg.aircraft_type_code,
      engine_type_code: reg.engine_type_code,
      manufacturer: aircraft_type&.manufacturer,
      model: aircraft_type&.model,
      aircraft_type: aircraft_type&.aircraft_type,
      engine_type: aircraft_type&.engine_type,
      num_engines: aircraft_type&.num_engines,
      num_seats: aircraft_type&.num_seats,
      weight_class: aircraft_type&.weight_class
    }
  end

  def close
    # No-op for ActiveRecord version
  end

  def count_registrations
    Registration.count
  end
end
