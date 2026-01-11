# frozen_string_literal: true

require_relative "constants"
require_relative "logging"
require_relative "flight_history"

# AircraftTracker - Manages aircraft state and position tracking
# Extracted from SDRReceiver to separate concerns
class AircraftTracker
  include ADSB::Constants

  attr_reader :aircraft, :history, :stats

  def initialize(config:)
    @config = config
    @aircraft = {}
    @callbacks = []
    @mutex = Mutex.new
    @history = FlightHistory.new
    @last_history_save = {}

    # ICAO recovery for short messages
    @icao_candidates = []
    @last_candidate_refresh = Time.now - 300  # Force initial refresh

    @stats = {
      messages_total: 0,
      messages_position: 0,
      messages_velocity: 0,
      messages_identification: 0,
      messages_squawk: 0,
      messages_recovered: 0,
      messages_filtered: 0,
      messages_crc_fixed: 0
    }
  end

  # Register a callback for aircraft updates
  def on_aircraft_update(&block)
    @callbacks << block
  end

  # Get current aircraft list (removes stale entries)
  def aircraft_list
    @mutex.synchronize do
      now = Time.now
      @aircraft.delete_if { |_, data| now - data[:last_seen] > AIRCRAFT_TIMEOUT_SEC }
      @aircraft.values
    end
  end

  # Get stats (for merging with receiver stats)
  def get_stats
    @mutex.synchronize { @stats.dup }
  end

  # Process decoded messages and update aircraft state
  def process_messages(messages)
    # Refresh ICAO candidates periodically
    refresh_icao_candidates if Time.now - @last_candidate_refresh > ICAO_CANDIDATE_REFRESH_SEC

    messages.each do |msg|
      # Attempt ICAO recovery for short messages
      if msg.needs_icao_recovery?
        recovered_icao = attempt_icao_recovery(msg)
        if recovered_icao
          msg.set_recovered_icao(recovered_icao)
          @mutex.synchronize { @stats[:messages_recovered] += 1 }
        else
          next
        end
      end

      # Track CRC-fixed messages
      if msg.crc_fixed?
        @mutex.synchronize { @stats[:messages_crc_fixed] += 1 }
      end

      # Apply show_only ICAO filter
      if @config.show_only && msg.icao != @config.show_only
        @mutex.synchronize { @stats[:messages_filtered] += 1 }
        next
      end

      update_aircraft(msg)
    end
  end

  private

  def refresh_icao_candidates
    @last_candidate_refresh = Time.now

    # Start with in-memory aircraft (most likely matches)
    candidates = @aircraft.keys

    # Add recently seen from database
    begin
      db_candidates = @history.recent_icaos(hours: ICAO_CANDIDATE_HOURS)
      candidates += db_candidates
    rescue StandardError => e
      ADSB.logger.warn "Could not load ICAO candidates from database: #{e.message}"
    end

    @icao_candidates = candidates.uniq
  end

  def attempt_icao_recovery(msg)
    candidates = @aircraft.keys + @icao_candidates
    candidates.uniq!

    ADSBDecoder::ICAORecovery.recover(msg.raw, candidates)
  end

  def update_aircraft(msg)
    icao = msg.icao

    @mutex.synchronize do
      @stats[:messages_total] += 1

      @aircraft[icao] ||= {
        icao: icao,
        callsign: nil,
        latitude: nil,
        longitude: nil,
        altitude: nil,
        speed: nil,
        heading: nil,
        vertical_rate: nil,
        squawk: nil,
        signal_strength: nil,
        last_seen: Time.now,
        messages: 0,
        even_position: nil,
        odd_position: nil,
        position_history: []
      }

      aircraft = @aircraft[icao]
      aircraft[:last_seen] = Time.now
      aircraft[:messages] += 1

      update_identification(aircraft, msg)
      update_position(aircraft, msg)
      update_velocity(aircraft, msg)
      update_squawk(aircraft, msg)
      update_ehs_data(aircraft, msg)
      update_signal_strength(aircraft, msg)

      save_to_history(aircraft)
      notify_callbacks(aircraft)
    end
  end

  def update_identification(aircraft, msg)
    return unless msg.identification?

    aircraft[:callsign] = msg.callsign
    @stats[:messages_identification] += 1
  end

  def update_position(aircraft, msg)
    return unless msg.airborne_position? || msg.surface_position?

    aircraft[:altitude] = msg.altitude
    @stats[:messages_position] += 1

    cpr = msg.cpr_position
    return unless cpr

    if cpr[:odd]
      aircraft[:odd_position] = { msg: msg, time: Time.now }
    else
      aircraft[:even_position] = { msg: msg, time: Time.now }
    end

    try_decode_position(aircraft)
  end

  def update_velocity(aircraft, msg)
    return unless msg.velocity?

    @stats[:messages_velocity] += 1
    vel = msg.velocity
    return unless vel

    aircraft[:speed] = vel[:speed]
    aircraft[:heading] = vel[:heading]
    aircraft[:vertical_rate] = vel[:vertical_rate]
  end

  def update_squawk(aircraft, msg)
    return unless msg.identity_reply?

    squawk = msg.squawk
    return unless squawk

    aircraft[:squawk] = squawk
    @stats[:messages_squawk] += 1
  end

  def update_ehs_data(aircraft, msg)
    return unless msg.comm_b?

    ehs = msg.ehs_data
    return unless ehs

    aircraft[:selected_altitude] = ehs[:selected_altitude] if ehs[:selected_altitude]
    aircraft[:roll_angle] = ehs[:roll_angle] if ehs[:roll_angle]
    aircraft[:track_angle] = ehs[:track_angle] if ehs[:track_angle]
    aircraft[:ground_speed] = ehs[:ground_speed] if ehs[:ground_speed]
    aircraft[:magnetic_heading] = ehs[:magnetic_heading] if ehs[:magnetic_heading]
    aircraft[:indicated_airspeed] = ehs[:indicated_airspeed] if ehs[:indicated_airspeed]
    aircraft[:mach] = ehs[:mach] if ehs[:mach]
    aircraft[:baro_rate] = ehs[:baro_rate] if ehs[:baro_rate]
  end

  def update_signal_strength(aircraft, msg)
    return unless msg.signal_strength

    if aircraft[:signal_strength]
      aircraft[:signal_strength] = (aircraft[:signal_strength] * SIGNAL_STRENGTH_OLD_WEIGHT +
                                    msg.signal_strength * SIGNAL_STRENGTH_NEW_WEIGHT).round(6)
    else
      aircraft[:signal_strength] = msg.signal_strength.round(6)
    end
  end

  def save_to_history(aircraft)
    icao = aircraft[:icao]
    now = Time.now

    last_save = @last_history_save[icao]
    return if last_save && (now - last_save) < HISTORY_SAVE_INTERVAL_SEC

    @last_history_save[icao] = now

    @history.record_aircraft(icao, aircraft[:callsign])
    @history.record_sighting(aircraft)
  rescue StandardError => e
    ADSB.logger.error "History save error: #{e.message}"
  end

  def try_decode_position(aircraft)
    even = aircraft[:even_position]
    odd = aircraft[:odd_position]

    return unless even && odd
    return if (even[:time] - odd[:time]).abs > CPR_FRAME_MAX_AGE_SEC

    position = ADSBDecoder.decode_position(even[:msg], odd[:msg])
    return unless position

    lat = position[:latitude].round(6)
    lon = position[:longitude].round(6)

    # Apply max_range filter if receiver position is set
    if @config.has_receiver_position?
      distance = calculate_distance(
        @config.receiver_lat, @config.receiver_lon,
        lat, lon
      )

      if distance > @config.max_range_nm
        ADSB.logger.debug "Position rejected: #{aircraft[:icao]} at #{distance.round(1)}nm exceeds max range #{@config.max_range_nm}nm"
        return
      end

      aircraft[:distance] = distance.round(1)
    end

    aircraft[:latitude] = lat
    aircraft[:longitude] = lon

    aircraft[:position_history] << {
      lat: lat,
      lon: lon,
      alt: aircraft[:altitude],
      time: Time.now.to_i
    }
    aircraft[:position_history] = aircraft[:position_history].last(MAX_POSITION_HISTORY)
  end

  def calculate_distance(lat1, lon1, lat2, lon2)
    lat1_rad = lat1 * DEGREES_TO_RADIANS
    lat2_rad = lat2 * DEGREES_TO_RADIANS
    delta_lat = (lat2 - lat1) * DEGREES_TO_RADIANS
    delta_lon = (lon2 - lon1) * DEGREES_TO_RADIANS

    a = Math.sin(delta_lat / 2)**2 +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(delta_lon / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    EARTH_RADIUS_NM * c
  end

  def notify_callbacks(aircraft)
    data = aircraft.reject { |k, _| %i[even_position odd_position].include?(k) }

    @callbacks.each do |callback|
      callback.call(data)
    rescue StandardError => e
      ADSB.logger.error "Callback error: #{e.message}"
    end
  end
end
