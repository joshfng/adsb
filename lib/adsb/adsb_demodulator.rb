# frozen_string_literal: true

require_relative 'constants'
require_relative 'logging'
require_relative 'adsb_decoder'

# ADS-B Demodulator
# Converts raw I/Q samples to decoded ADS-B messages
class ADSBDemodulator
  include ADSB::Constants

  # Derived constant for full message detection
  FULL_MESSAGE_SAMPLES = PREAMBLE_SAMPLES + LONG_MESSAGE_SAMPLES

  def initialize(fix_errors: true, crc_check: true)
    @fix_errors = fix_errors
    @crc_check = crc_check
    @decode_options = { fix_errors: fix_errors, crc_check: crc_check }

    @mutex = Mutex.new
    @preamble_count = 0
    @preamble_total = 0
    @valid_msg_count = 0
    @crc_fail_count = 0
    @crc_fail_total = 0
    @crc_fixed_count = 0
    @last_stats_time = Time.now
    @sample_count = 0
    @df17_debug_count = 0
  end

  def stats
    @mutex.synchronize do
      {
        preambles: @preamble_total,
        crc_failures: @crc_fail_total,
        crc_fixed: @crc_fixed_count,
        valid_messages: @valid_msg_count
      }
    end
  end

  def process_samples(samples)
    messages = []

    @mutex.synchronize { @sample_count += samples.length }

    # Convert to magnitude using Complex#abs (faster than manual sqrt)
    magnitudes = samples.map(&:abs)

    # Scan for preambles
    i = 0
    while i < magnitudes.length - FULL_MESSAGE_SAMPLES
      preamble_result = detect_preamble_improved(magnitudes, i)

      if preamble_result
        @mutex.synchronize do
          @preamble_count += 1
          @preamble_total += 1
        end
        signal_level = preamble_result[:level]

        # Try long message (112 bits) first
        bits = demodulate_message(magnitudes, i + PREAMBLE_SAMPLES, signal_level, LONG_MESSAGE_BITS)
        msg = bits ? ADSBDecoder.decode(bits, @decode_options) : nil

        # If long message failed, try short message (56 bits) for DF4/DF5/DF11
        if !msg&.valid?
          short_bits = demodulate_message(magnitudes, i + PREAMBLE_SAMPLES, signal_level, SHORT_MESSAGE_BITS)
          if short_bits
            short_msg = ADSBDecoder.decode(short_bits, @decode_options)
            if short_msg&.valid?
              msg = short_msg
              bits = short_bits
            end
          end
        end

        if msg&.valid?
          @mutex.synchronize do
            @valid_msg_count += 1
            @crc_fixed_count += 1 if msg.crc_fixed?
          end
          msg.signal_strength = signal_level
          messages << msg
          fix_note = msg.crc_fixed? ? " [FIXED bit #{msg.error_bit}]" : ''
          ADSB.logger.debug "[ADSB] ICAO=#{msg.icao} DF=#{msg.df} TC=#{msg.tc} sig=#{(signal_level * 1000).round}#{fix_note} #{describe_message(msg)}"
        elsif bits
          @mutex.synchronize do
            @crc_fail_count += 1
            @crc_fail_total += 1
          end
          # Debug DF=17 failures (real ADS-B)
          df = (bits[0..4].join.to_i(2))
          if df == 17
            should_log = @mutex.synchronize do
              if @df17_debug_count < MAX_DF17_DEBUG_FAILURES
                @df17_debug_count += 1
                true
              else
                false
              end
            end
            if should_log
              hex = bits_to_hex(bits)
              ADSB.logger.debug "DF17 CRC fail: #{hex}"
            end
          end
        end

        i += FULL_MESSAGE_SAMPLES
      else
        i += 1
      end
    end

    log_stats if Time.now - @last_stats_time > DEMOD_STATS_INTERVAL_SEC
    messages
  end

  private

  def describe_message(msg)
    parts = []
    if msg.identification? && msg.callsign
      parts << "CALLSIGN=#{msg.callsign}"
    end
    parts << "alt=#{msg.altitude}ft" if msg.airborne_position? && msg.altitude
    if msg.velocity?
      vel = msg.velocity
      parts << "spd=#{vel[:speed]}kt hdg=#{vel[:heading]}" if vel
    end
    if msg.identity_reply?
      squawk = msg.squawk
      parts << "SQUAWK=#{squawk}" if squawk
    end
    if msg.comm_b?
      ehs = msg.ehs_data
      if ehs
        parts << "BDS=#{ehs[:bds]}"
        parts << "selAlt=#{ehs[:selected_altitude]}ft" if ehs[:selected_altitude]
        parts << "roll=#{ehs[:roll_angle]}°" if ehs[:roll_angle]
        parts << "hdg=#{ehs[:magnetic_heading]}°" if ehs[:magnetic_heading]
        parts << "ias=#{ehs[:indicated_airspeed]}kt" if ehs[:indicated_airspeed]
        parts << "mach=#{ehs[:mach]}" if ehs[:mach]
      end
    end
    parts.join(' ')
  end

  def log_stats
    preamble_count, crc_fail_count, sample_count = @mutex.synchronize do
      pc = @preamble_count
      cfc = @crc_fail_count
      sc = @sample_count
      @preamble_count = 0
      @crc_fail_count = 0
      @sample_count = 0
      [pc, cfc, sc]
    end

    elapsed = Time.now - @last_stats_time + 0.001
    rate = sample_count / elapsed / 1_000_000
    ADSB.logger.debug "Demod: Preambles=#{preamble_count} Valid=#{@valid_msg_count} CRC_fail=#{crc_fail_count} Rate=#{rate.round(1)}MS/s"
    @last_stats_time = Time.now
  end

  def bits_to_hex(bits)
    bytes = bits.each_slice(4).map { |nibble| nibble.join.to_i(2) }
    bytes.map { |b| b.to_s(16).upcase }.join
  end

  # Preamble detection for 2 MHz sample rate (dump1090-style)
  # Mode S preamble pattern at 2 samples/μs:
  #   Sample 0: HIGH (pulse)
  #   Sample 1: low
  #   Sample 2: HIGH (pulse)
  #   Sample 3: low
  #   Sample 4-6: low (gap)
  #   Sample 7: HIGH (pulse)
  #   Sample 8: low
  #   Sample 9: HIGH (pulse)
  #   Sample 10-15: low (quiet zone before data)
  def detect_preamble_improved(magnitudes, offset)
    return nil if offset + FULL_MESSAGE_SAMPLES > magnitudes.length

    # dump1090's relationship checks between adjacent samples
    return nil unless magnitudes[offset] > magnitudes[offset + 1] &&      # pulse 0 > gap 1
                      magnitudes[offset + 1] < magnitudes[offset + 2] &&  # gap 1 < pulse 2
                      magnitudes[offset + 2] > magnitudes[offset + 3] &&  # pulse 2 > gap 3
                      magnitudes[offset + 3] < magnitudes[offset] &&      # gap 3 < pulse 0
                      magnitudes[offset + 4] < magnitudes[offset] &&      # gap 4 < pulse 0
                      magnitudes[offset + 5] < magnitudes[offset] &&      # gap 5 < pulse 0
                      magnitudes[offset + 6] < magnitudes[offset] &&      # gap 6 < pulse 0
                      magnitudes[offset + 7] > magnitudes[offset + 8] &&  # pulse 7 > gap 8
                      magnitudes[offset + 8] < magnitudes[offset + 9] &&  # gap 8 < pulse 9
                      magnitudes[offset + 9] > magnitudes[offset + 6]     # pulse 9 > gap 6

    # Average pulse level (divide by 6 like dump1090 for lower threshold)
    high = (magnitudes[offset] + magnitudes[offset + 2] + magnitudes[offset + 7] + magnitudes[offset + 9]) / 6.0

    # Minimum signal level - reject pure noise
    return nil if high < MIN_SIGNAL_LEVEL

    # Gap samples must be below threshold
    return nil if magnitudes[offset + 4] >= high || magnitudes[offset + 5] >= high

    # Quiet zone before data must be low
    return nil if magnitudes[offset + 11] >= high ||
                  magnitudes[offset + 12] >= high ||
                  magnitudes[offset + 13] >= high ||
                  magnitudes[offset + 14] >= high

    { level: high }
  end

  # Bit demodulation for 2 MHz sample rate (dump1090-style)
  # Each bit is 1μs = 2 samples at 2 MHz
  # PPM encoding: pulse in first half = 1, pulse in second half = 0
  def demodulate_message(magnitudes, offset, signal_level, num_bits = LONG_MESSAGE_BITS)
    num_samples = num_bits * 2
    return nil if offset + num_samples > magnitudes.length

    bits = Array.new(num_bits)
    delta_sum = 0.0
    phase_correction = 1.0  # Start with no correction

    num_bits.times do |bit_idx|
      base = offset + bit_idx * 2

      # Apply phase correction to first half
      first_half = magnitudes[base] * phase_correction
      second_half = magnitudes[base + 1]

      delta = (first_half - second_half).abs
      delta_sum += delta

      # Determine bit value
      if bit_idx > 0 && delta < LOW_CONFIDENCE_BIT_THRESHOLD
        bits[bit_idx] = bits[bit_idx - 1]  # Copy previous bit
      elsif first_half > second_half
        bits[bit_idx] = 1
      else
        bits[bit_idx] = 0
      end

      # Set phase correction for next bit based on current bit
      phase_correction = bits[bit_idx] == 1 ? PHASE_CORRECTION_AMPLIFY : PHASE_CORRECTION_DAMPEN
    end

    # Check average delta - reject if too low (likely noise)
    return nil if delta_sum < MIN_BIT_DELTA * num_bits

    bits
  end
end
