# frozen_string_literal: true

require_relative "constants"

# Configuration for SDR receiver
# Provides dump1090-compatible options
class SDRConfig
  include ADSB::Constants

  attr_accessor :device_index, :gain, :frequency,
                :receiver_lat, :receiver_lon, :max_range_nm,
                :fix_errors, :crc_check, :show_only,
                :snip_level, :dump_raw

  def initialize(options = {})
    @device_index = options.fetch(:device_index, 0)
    @gain = options.fetch(:gain, :max)  # :max or dB value
    @frequency = options.fetch(:frequency, FREQUENCY_HZ)
    @receiver_lat = options.fetch(:receiver_lat, nil)
    @receiver_lon = options.fetch(:receiver_lon, nil)
    @max_range_nm = options.fetch(:max_range_nm, 300)
    @fix_errors = options.fetch(:fix_errors, true)  # --fix is default
    @crc_check = options.fetch(:crc_check, true)
    @show_only = options.fetch(:show_only, nil)  # ICAO hex to filter
    @snip_level = options.fetch(:snip_level, nil)
    @dump_raw = options.fetch(:dump_raw, nil)
  end

  # Convert gain setting to tenths of dB for rtlsdr gem
  def gain_tenths_db
    case @gain
    when :max
      DEFAULT_GAIN_TENTHS_DB
    else
      (@gain.to_f * 10).to_i
    end
  end

  # Whether we have a receiver position for surface position decoding
  def has_receiver_position?
    !@receiver_lat.nil? && !@receiver_lon.nil?
  end

  # Convert to hash for passing to receiver
  def to_h
    {
      device_index: @device_index,
      gain: @gain,
      frequency: @frequency,
      receiver_lat: @receiver_lat,
      receiver_lon: @receiver_lon,
      max_range_nm: @max_range_nm,
      fix_errors: @fix_errors,
      crc_check: @crc_check,
      show_only: @show_only,
      snip_level: @snip_level,
      dump_raw: @dump_raw
    }
  end

  # Create from environment variables (for web mode)
  def self.from_env
    new(
      device_index: ENV.fetch("ADSB_DEVICE_INDEX", "0").to_i,
      gain: parse_gain(ENV["ADSB_GAIN"]),
      frequency: ENV.fetch("ADSB_FREQUENCY", FREQUENCY_HZ.to_s).to_i,
      receiver_lat: ENV["ADSB_LAT"]&.to_f,
      receiver_lon: ENV["ADSB_LON"]&.to_f,
      max_range_nm: ENV.fetch("ADSB_MAX_RANGE", "300").to_i,
      fix_errors: ENV["ADSB_NO_FIX"] != "1",
      crc_check: ENV["ADSB_NO_CRC_CHECK"] != "1",
      show_only: ENV["ADSB_SHOW_ONLY"]&.upcase,
      snip_level: ENV["ADSB_SNIP"]&.to_f,
      dump_raw: ENV["ADSB_DUMP_RAW"]
    )
  end

  # Parse gain value from string
  def self.parse_gain(value)
    return :max if value.nil? || value.empty? || value == "max"
    value.to_f
  end
end
