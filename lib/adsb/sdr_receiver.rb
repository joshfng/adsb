# frozen_string_literal: true

require "rtlsdr"
require_relative "constants"
require_relative "logging"
require_relative "sdr_config"
require_relative "adsb_demodulator"
require_relative "aircraft_tracker"

# SDR Receiver for ADS-B
# Wraps the rtlsdr gem to receive and decode ADS-B signals
class SDRReceiver
  include ADSB::Constants

  attr_reader :running, :config

  def initialize(config: nil, device_index: 0)
    @config = config || SDRConfig.new(device_index: device_index)
    @device = nil
    @demodulator = ADSBDemodulator.new(
      fix_errors: @config.fix_errors,
      crc_check: @config.crc_check
    )
    @running = false
    @mutex = Mutex.new
    @tracker = AircraftTracker.new(config: @config)

    @stats = {
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
    @dump_file&.close
    @dump_file = nil
    close_device
    ADSB.logger.info "Receiver stopped"
  end

  # Get current stats (merged from receiver and tracker)
  def get_stats
    @mutex.synchronize do
      demod_stats = @demodulator.stats
      tracker_stats = @tracker.get_stats
      uptime = @stats[:start_time] ? (Time.now - @stats[:start_time]).to_i : 0

      @stats.merge(tracker_stats).merge(
        uptime_seconds: uptime,
        preambles_detected: demod_stats[:preambles],
        crc_failures: demod_stats[:crc_failures],
        sample_rate_mhz: @stats[:sample_rate] / 1_000_000.0,
        frequency_mhz: @stats[:frequency] / 1_000_000.0
      )
    end
  end

  # Legacy accessors for backward compatibility
  def aircraft
    @tracker.aircraft
  end

  def history
    @tracker.history
  end

  def on_aircraft_update(&block)
    @tracker.on_aircraft_update(&block)
  end

  def aircraft_list
    @tracker.aircraft_list
  end

  # Expose stats for testing
  def stats
    @mutex.synchronize { @stats.merge(@tracker.get_stats) }
  end

  private

  def open_device
    if @config.tcp?
      open_tcp_device
    else
      open_local_device
    end
  end

  def open_tcp_device
    host = @config.rtl_tcp_host
    port = @config.rtl_tcp_port

    ADSB.logger.info "Connecting to rtl_tcp server at #{host}:#{port}..."
    @device = RTLSDR.connect(host, port)
    ADSB.logger.info "Connected to #{@device.name} (tuner: #{@device.tuner_name})"
  rescue RTLSDR::ConnectionError => e
    raise "rtl_tcp connection failed: #{e.message}"
  end

  def open_local_device
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

    @device.sample_rate = SAMPLE_RATE_HZ
    @device.frequency = frequency
    @device.manual_gain_mode!
    @device.tuner_gain = gain_tenths
    @stats[:gain] = @device.tuner_gain / 10.0
    @stats[:frequency] = frequency

    ADSB.logger.info "Tuned to #{frequency / 1_000_000.0} MHz"
    ADSB.logger.info "Sample rate: #{SAMPLE_RATE_HZ / 1_000_000.0} MHz"
    ADSB.logger.info "Gain: #{@device.tuner_gain / 10.0} dB"

    if @config.has_receiver_position?
      ADSB.logger.info "Receiver position: #{@config.receiver_lat}, #{@config.receiver_lon}"
      ADSB.logger.info "Max range: #{@config.max_range_nm} nm"
    end

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

  def dump_raw_samples(samples)
    bytes = samples.flat_map do |s|
      i_byte = (s.real * 127.5 + 127.5).round.clamp(0, 255)
      q_byte = (s.imag * 127.5 + 127.5).round.clamp(0, 255)
      [ i_byte, q_byte ]
    end
    @dump_file.write(bytes.pack("C*"))
  end

  def process_samples(samples)
    if @config.snip_level
      samples = apply_snip_filter(samples)
    end

    messages = @demodulator.process_samples(samples)
    @tracker.process_messages(messages)
  end

  def apply_snip_filter(samples)
    level = @config.snip_level
    samples.select do |s|
      magnitude = Math.sqrt(s.real * s.real + s.imag * s.imag)
      magnitude >= level
    end
  end
end
