# frozen_string_literal: true

require "rtlsdr"
require_relative "constants"
require_relative "logging"
require_relative "sdr_config"
require_relative "adsb_demodulator"
require_relative "flight_history"

# SDR Receiver for ADS-B
# Wraps the rtlsdr gem to receive and decode ADS-B signals
class SDRReceiver
  include ADSB::Constants

  attr_reader :running, :aircraft, :stats, :history, :config

  def initialize(config: nil, device_index: 0)
    @config = config || SDRConfig.new(device_index: device_index)
    @device = nil
    @demodulator = ADSBDemodulator.new(
      fix_errors: @config.fix_errors,
      crc_check: @config.crc_check
    )
    @running = false
    @aircraft = {}
    @callbacks = []
    @mutex = Mutex.new
    @history = FlightHistory.new
    @last_history_save = {}  # Track when we last saved each aircraft to history

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
      messages_crc_fixed: 0,
      start_time: nil,
      sample_rate: SAMPLE_RATE_HZ,
      frequency: @config.frequency,
      gain: @config.gain
    }

    # Raw dump file for dump1090 compatibility
    @dump_file = nil
    dump_path = @config.dump_raw
    if dump_path
      @dump_file = File.open(dump_path, "wb")
      ADSB.logger.info "Dumping raw I/Q samples to: #{dump_path}"
    end
  end

  # Register a callback for new aircraft data
  def on_aircraft_update(&block)
    @callbacks << block
  end

  # Start receiving
  def start
    return if @running

    open_device
    configure_device
    @running = true
    @stats[:start_time] = Time.now
    @stats[:gain] = @device.tuner_gain / 10.0

    start_async_receive
  end

  # Stop receiving
  def stop
    return unless @running
    @running = false
    @device&.cancel_async if @device&.streaming?
    @receive_thread&.join(2)
    # Close dump file
    @dump_file&.close
    @dump_file = nil
    close_device
    ADSB.logger.info "Receiver stopped"
  end

  # Get current aircraft list
  def aircraft_list
    @mutex.synchronize do
      now = Time.now
      # Remove aircraft not seen recently
      @aircraft.delete_if { |_, data| now - data[:last_seen] > AIRCRAFT_TIMEOUT_SEC }
      @aircraft.values
    end
  end

  # Get current stats
  def get_stats
    @mutex.synchronize do
      demod_stats = @demodulator.stats
      uptime = @stats[:start_time] ? (Time.now - @stats[:start_time]).to_i : 0

      @stats.merge(
        uptime_seconds: uptime,
        preambles_detected: demod_stats[:preambles],
        crc_failures: demod_stats[:crc_failures],
        sample_rate_mhz: @stats[:sample_rate] / 1_000_000.0,
        frequency_mhz: @stats[:frequency] / 1_000_000.0
      )
    end
  end

  private

  def open_device
    device_count = RTLSDR.device_count
    raise "No RTL-SDR devices found" if device_count.zero?

    device_index = @config.device_index
    raise "Invalid device index: #{device_index}" if device_index >= device_count

    ADSB.logger.info "Found #{device_count} RTL-SDR device(s)"
    ADSB.logger.info "Opening device #{device_index}: #{RTLSDR.device_name(device_index)}"

    @device = RTLSDR.open(device_index)
  end

  def configure_device
    frequency = @config.frequency
    gain_tenths = @config.gain_tenths_db

    # Configure basic settings
    @device.sample_rate = SAMPLE_RATE_HZ
    @device.frequency = frequency

    # Configure gain (manual mode, max gain is best for ADS-B)
    @device.manual_gain_mode!
    @device.tuner_gain = gain_tenths
    @stats[:gain] = @device.tuner_gain / 10.0
    @stats[:frequency] = frequency

    ADSB.logger.info "Tuned to #{frequency / 1_000_000.0} MHz"
    ADSB.logger.info "Sample rate: #{SAMPLE_RATE_HZ / 1_000_000.0} MHz"
    ADSB.logger.info "Gain: #{@device.tuner_gain / 10.0} dB"

    # Log receiver position if set
    if @config.has_receiver_position?
      ADSB.logger.info "Receiver position: #{@config.receiver_lat}, #{@config.receiver_lon}"
      ADSB.logger.info "Max range: #{@config.max_range_nm} nm"
    end

    # Log filters
    ADSB.logger.info "Show only ICAO: #{@config.show_only}" if @config.show_only
    ADSB.logger.info "CRC error correction: " + (@config.fix_errors ? "enabled" : "disabled")
    ADSB.logger.info "CRC check: " + (@config.crc_check ? "enabled" : "DISABLED (not recommended)")
  end

  def close_device
    @device&.close
    @device = nil
  end

  def start_async_receive
    ADSB.logger.info "Starting ADS-B reception..."

    # Use sync read in a thread - gem releases GVL during USB reads
    @receive_thread = Thread.new do
      while @running
        begin
          samples = @device.read_samples(SAMPLES_PER_READ)
          dump_raw_samples(samples) if @dump_file
          process_samples(samples)
        rescue StandardError => e
          ADSB.logger.error "Receive error: #{e.message}"
          sleep 0.1 if @running
        end
      end
    end

    ADSB.logger.info "Receiver started"
  end

  # Convert Complex samples back to 8-bit unsigned I/Q format for dump1090
  def dump_raw_samples(samples)
    # dump1090 expects raw 8-bit unsigned I/Q pairs
    # The rtlsdr gem normalizes samples to -1..1 range
    # Convert back: byte = (value * 127.5 + 127.5).round.clamp(0, 255)
    bytes = samples.flat_map do |s|
      i_byte = (s.real * 127.5 + 127.5).round.clamp(0, 255)
      q_byte = (s.imag * 127.5 + 127.5).round.clamp(0, 255)
      [ i_byte, q_byte ]
    end
    @dump_file.write(bytes.pack("C*"))
  end

  def process_samples(samples)
    # Apply snip filter if configured
    if @config.snip_level
      samples = apply_snip_filter(samples)
    end

    messages = @demodulator.process_samples(samples)

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
          # Skip messages where we couldn't recover the ICAO
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

  def apply_snip_filter(samples)
    level = @config.snip_level
    samples.select do |s|
      magnitude = Math.sqrt(s.real * s.real + s.imag * s.imag)
      magnitude >= level
    end
  end

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
    # Build candidate list: in-memory first (fastest), then cached DB candidates
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

      # Update based on message type
      if msg.identification?
        aircraft[:callsign] = msg.callsign
        @stats[:messages_identification] += 1
      end

      if msg.airborne_position? || msg.surface_position?
        aircraft[:altitude] = msg.altitude
        @stats[:messages_position] += 1

        # Store CPR position for later decoding
        cpr = msg.cpr_position
        if cpr
          if cpr[:odd]
            aircraft[:odd_position] = { msg: msg, time: Time.now }
          else
            aircraft[:even_position] = { msg: msg, time: Time.now }
          end

          # Try to decode position if we have both frames
          try_decode_position(aircraft)
        end
      end

      if msg.velocity?
        @stats[:messages_velocity] += 1
        vel = msg.velocity
        if vel
          aircraft[:speed] = vel[:speed]
          aircraft[:heading] = vel[:heading]
          aircraft[:vertical_rate] = vel[:vertical_rate]
        end
      end

      # Extract squawk from identity reply messages (DF5, DF21)
      if msg.identity_reply?
        squawk = msg.squawk
        if squawk
          aircraft[:squawk] = squawk
          @stats[:messages_squawk] += 1
        end
      end

      # Extract EHS data from Comm-B messages (DF20, DF21)
      if msg.comm_b?
        ehs = msg.ehs_data
        if ehs
          aircraft[:selected_altitude] = ehs[:selected_altitude] if ehs[:selected_altitude]
          aircraft[:roll_angle] = ehs[:roll_angle] if ehs[:roll_angle]
          aircraft[:track_angle] = ehs[:track_angle] if ehs[:track_angle]
          aircraft[:ground_speed] = ehs[:ground_speed] if ehs[:ground_speed]
          aircraft[:magnetic_heading] = ehs[:magnetic_heading] if ehs[:magnetic_heading]
          aircraft[:indicated_airspeed] = ehs[:indicated_airspeed] if ehs[:indicated_airspeed]
          aircraft[:mach] = ehs[:mach] if ehs[:mach]
          aircraft[:baro_rate] = ehs[:baro_rate] if ehs[:baro_rate]
        end
      end

      # Update signal strength (exponential moving average)
      if msg.signal_strength
        if aircraft[:signal_strength]
          aircraft[:signal_strength] = (aircraft[:signal_strength] * SIGNAL_STRENGTH_OLD_WEIGHT +
                                        msg.signal_strength * SIGNAL_STRENGTH_NEW_WEIGHT).round(6)
        else
          aircraft[:signal_strength] = msg.signal_strength.round(6)
        end
      end

      # Record to history (every 30 seconds per aircraft to avoid spam)
      save_to_history(aircraft)

      notify_callbacks(aircraft)
    end
  end

  def save_to_history(aircraft)
    icao = aircraft[:icao]
    now = Time.now

    # Only save periodically per aircraft
    last_save = @last_history_save[icao]
    return if last_save && (now - last_save) < HISTORY_SAVE_INTERVAL_SEC

    @last_history_save[icao] = now

    # Record aircraft and sighting (fast with WAL mode)
    @history.record_aircraft(icao, aircraft[:callsign])
    @history.record_sighting(aircraft)
  rescue StandardError => e
    ADSB.logger.error "History save error: #{e.message}"
  end

  def try_decode_position(aircraft)
    even = aircraft[:even_position]
    odd = aircraft[:odd_position]

    return unless even && odd

    # Both frames should be recent
    return if (even[:time] - odd[:time]).abs > CPR_FRAME_MAX_AGE_SEC

    position = ADSBDecoder.decode_position(even[:msg], odd[:msg])

    if position
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

      # Add to position history for flight trails
      aircraft[:position_history] << {
        lat: lat,
        lon: lon,
        alt: aircraft[:altitude],
        time: Time.now.to_i
      }
      # Keep only recent positions
      aircraft[:position_history] = aircraft[:position_history].last(MAX_POSITION_HISTORY)
    end
  end

  # Calculate distance between two points using Haversine formula
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
    # Create a copy without internal position tracking data
    data = aircraft.reject { |k, _| %i[even_position odd_position].include?(k) }

    @callbacks.each do |callback|
      callback.call(data)
    rescue StandardError => e
      ADSB.logger.error "Callback error: #{e.message}"
    end
  end
end
