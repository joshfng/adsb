# frozen_string_literal: true

require_relative 'constants'

# ADS-B Message Decoder
# Decodes Mode S Extended Squitter (DF17) and other Mode S messages
module ADSBDecoder
  include ADSB::Constants

  # Default decode options
  @default_options = {
    fix_errors: true,
    crc_check: true
  }

  # Mutex for thread-safe syndrome table initialization
  @syndrome_mutex = Mutex.new

  # Precomputed CRC syndrome table for single-bit error correction
  # syndrome_table[syndrome] = bit_position_to_flip
  # This allows O(1) error correction instead of O(n) trial-and-error
  @syndrome_table = nil

  class << self
    attr_accessor :default_options, :syndrome_table

    # Build syndrome lookup table for 112-bit messages
    # Each entry maps a CRC syndrome to the bit position that caused it
    # Thread-safe with double-checked locking
    def build_syndrome_table
      return @syndrome_table if @syndrome_table

      @syndrome_mutex.synchronize do
        # Double-check after acquiring lock
        return @syndrome_table if @syndrome_table

        table = {}
        poly = ADSB::Constants::CRC24_POLY & 0xFFFFFF

        # For each bit position, compute what syndrome results from
        # flipping just that bit in an otherwise-zero message
        112.times do |bit_pos|
          # Create a message with just one bit set
          syndrome = compute_single_bit_syndrome(bit_pos, poly)
          table[syndrome] = bit_pos
        end

        @syndrome_table = table
      end

      @syndrome_table
    end

    private

    def syndrome_mutex
      @syndrome_mutex
    end

    # Compute the CRC syndrome for a single bit error at position bit_pos
    def compute_single_bit_syndrome(bit_pos, poly)
      # The syndrome for a bit error at position P is equivalent to
      # computing CRC over a message of all zeros except bit P = 1
      crc = 0
      112.times do |i|
        bit = (i == bit_pos) ? 1 : 0
        msb_out = (crc >> 23) & 1
        crc = ((crc << 1) | bit) & 0xFFFFFF
        crc ^= poly if msb_out == 1
      end
      crc
    end
  end

  class Message
    include ADSB::Constants

    attr_reader :raw, :df, :ca, :icao, :tc, :data, :crc_ok, :crc_fixed, :error_bit
    attr_accessor :signal_strength, :icao_recovered

    def initialize(bits, options = {})
      @raw = bits.dup
      @crc_fixed = false
      @error_bit = nil
      @icao_recovered = false

      fix_errors = options.fetch(:fix_errors, ADSBDecoder.default_options[:fix_errors])
      crc_check = options.fetch(:crc_check, ADSBDecoder.default_options[:crc_check])

      if crc_check
        @crc_ok = verify_crc(@raw)

        # Attempt single-bit error correction if enabled
        if !@crc_ok && fix_errors && bits.length == LONG_MESSAGE_BITS
          @crc_ok = attempt_single_bit_fix
        end
      else
        # Skip CRC check entirely (discouraged)
        @crc_ok = true
      end

      return unless @crc_ok

      parse_message(@raw)
    end

    # Was this message fixed by single-bit error correction?
    def crc_fixed?
      @crc_fixed
    end

    # Update ICAO after successful recovery from short message
    def set_recovered_icao(new_icao)
      @icao = new_icao
      @icao_recovered = true
    end

    # Check if this is a short message that needs ICAO recovery
    def needs_icao_recovery?
      @raw.length == SHORT_MESSAGE_BITS && [DF_ALTITUDE_REPLY, DF_IDENTITY_REPLY].include?(@df)
    end

    def valid?
      return false unless @crc_ok

      # Check DF validity based on message length
      if @raw.length == LONG_MESSAGE_BITS
        # Long messages: DF17 (ADS-B), DF20 (Comm-B Alt), DF21 (Comm-B Identity)
        [DF_ADSB, DF_COMM_B_ALT, DF_COMM_B_IDENTITY].include?(@df)
      else
        # Short messages: DF4 (Alt Reply), DF5 (Identity Reply)
        [DF_ALTITUDE_REPLY, DF_IDENTITY_REPLY].include?(@df)
      end
    end

    def adsb?
      @df == DF_ADSB
    end

    def identity_reply?
      @df == DF_IDENTITY_REPLY || @df == DF_COMM_B_IDENTITY
    end

    def identification?
      TC_IDENTIFICATION.include?(@tc)
    end

    def surface_position?
      TC_SURFACE_POSITION.include?(@tc)
    end

    def airborne_position?
      TC_AIRBORNE_POSITION_BARO.include?(@tc) || TC_AIRBORNE_POSITION_GNSS.include?(@tc)
    end

    def velocity?
      TC_AIRBORNE_VELOCITY.include?(@tc)
    end

    # Decode squawk code from identity reply messages (DF5, DF21)
    def squawk
      return nil unless identity_reply?

      # Identity code is in bits 19-31 (13 bits) for DF5/DF21
      # The format is: C1 A1 C2 A2 C4 A4 _ B1 D1 B2 D2 B4 D4
      # We need to decode this to get the 4-digit octal squawk code
      id_bits = @raw[19, 13]

      # Extract the bits according to Mode A format
      c1 = id_bits[0]
      a1 = id_bits[1]
      c2 = id_bits[2]
      a2 = id_bits[3]
      c4 = id_bits[4]
      a4 = id_bits[5]
      # bit 6 is unused (X bit)
      b1 = id_bits[7]
      d1 = id_bits[8]
      b2 = id_bits[9]
      d2 = id_bits[10]
      b4 = id_bits[11]
      d4 = id_bits[12]

      # Reconstruct 4-digit octal squawk: A, B, C, D
      a = a4 * 4 + a2 * 2 + a1
      b = b4 * 4 + b2 * 2 + b1
      c = c4 * 4 + c2 * 2 + c1
      d = d4 * 4 + d2 * 2 + d1

      format('%d%d%d%d', a, b, c, d)
    end

    # Check if this is a Comm-B message (DF20 or DF21) with EHS data
    def comm_b?
      @df == DF_COMM_B_ALT || @df == DF_COMM_B_IDENTITY
    end

    # Decode Enhanced Surveillance (EHS) data from Comm-B messages
    # Returns hash with BDS register data, or nil if not an EHS message
    def ehs_data
      return nil unless comm_b?
      return nil unless @data && @data.length >= 56

      # Try to identify BDS register from content
      # BDS registers are inferred since they're not explicitly transmitted
      bds = infer_bds_register

      case bds
      when '4,0'
        decode_bds40
      when '5,0'
        decode_bds50
      when '6,0'
        decode_bds60
      else
        nil
      end
    end

    private

    # Infer BDS register type from MB field content
    def infer_bds_register
      return nil unless @data && @data.length >= 56

      # BDS 4,0: Selected altitude - check for valid status bits
      if bds40_valid?
        return '4,0'
      end

      # BDS 5,0: Track and turn report
      if bds50_valid?
        return '5,0'
      end

      # BDS 6,0: Heading and speed
      if bds60_valid?
        return '6,0'
      end

      nil
    end

    def bds40_valid?
      # BDS 4,0 status bits: bit 1 (MCP/FCU selected altitude status)
      # and bit 14 (FMS selected altitude status)
      status1 = @data[0] == 1
      status2 = @data[13] == 1

      # At least one status should be set, and values should be reasonable
      return false unless status1 || status2

      if status1
        alt = bits_to_int(@data[1, 12]) * 16
        return false if alt < 0 || alt > 50000
      end

      true
    end

    def bds50_valid?
      # BDS 5,0: Roll angle status (bit 1), track angle status (bit 12)
      roll_status = @data[0] == 1
      track_status = @data[11] == 1

      return false unless roll_status || track_status

      if roll_status
        roll_raw = bits_to_int(@data[1, 10])
        roll_sign = @data[1]
        # Roll angle should be reasonable (-90 to +90 degrees)
        roll = roll_sign == 1 ? -(roll_raw & 0x1FF) * ROLL_ANGLE_SCALE : roll_raw * ROLL_ANGLE_SCALE
        return false if roll.abs > 90
      end

      true
    end

    def bds60_valid?
      # BDS 6,0: Heading status (bit 0), airspeed status (bit 12)
      heading_status = @data[0] == 1
      airspeed_status = @data[12] == 1

      return false unless heading_status || airspeed_status

      if heading_status
        hdg_raw = bits_to_int(@data[2, 10])
        hdg = hdg_raw * HEADING_SCALE
        return false if hdg < 0 || hdg > 360
      end

      if airspeed_status
        ias = bits_to_int(@data[13, 10])
        return false if ias < 0 || ias > 500
      end

      true
    end

    # BDS 4,0: Selected vertical intention
    def decode_bds40
      result = { bds: '4,0' }

      # MCP/FCU selected altitude (bits 1-13)
      if @data[0] == 1
        alt_raw = bits_to_int(@data[1, 12])
        result[:selected_altitude] = alt_raw * BDS40_ALTITUDE_RESOLUTION
      end

      # FMS selected altitude (bits 14-26)
      if @data[13] == 1
        fms_alt_raw = bits_to_int(@data[14, 12])
        result[:fms_altitude] = fms_alt_raw * BDS40_ALTITUDE_RESOLUTION
      end

      # Barometric pressure setting (bits 27-38)
      if @data[26] == 1
        baro_raw = bits_to_int(@data[27, 12])
        result[:baro_setting] = (baro_raw * BARO_SETTING_SCALE + BARO_SETTING_OFFSET).round(1)
      end

      result
    end

    # BDS 5,0: Track and turn report
    def decode_bds50
      result = { bds: '5,0' }

      # Roll angle (bits 1-11)
      if @data[0] == 1
        roll_sign = @data[1]
        roll_raw = bits_to_int(@data[2, 9])
        roll = roll_raw * ROLL_ANGLE_SCALE
        result[:roll_angle] = (roll_sign == 1 ? -roll : roll).round(2)
      end

      # True track angle (bits 12-22)
      if @data[11] == 1
        track_sign = @data[12]
        track_raw = bits_to_int(@data[13, 10])
        track = track_raw * TRACK_ANGLE_SCALE
        result[:track_angle] = (track_sign == 1 ? 180 + track : track).round(2)
      end

      # Ground speed (bits 23-33)
      if @data[22] == 1
        gs_raw = bits_to_int(@data[23, 10])
        result[:ground_speed] = (gs_raw * GROUND_SPEED_RESOLUTION).round
      end

      # Track angle rate (bits 34-44)
      if @data[33] == 1
        tar_sign = @data[34]
        tar_raw = bits_to_int(@data[35, 9])
        tar = tar_raw * TRACK_RATE_SCALE
        result[:track_rate] = (tar_sign == 1 ? -tar : tar).round(3)
      end

      # True airspeed (bits 45-55)
      if @data[44] == 1
        tas_raw = bits_to_int(@data[45, 10])
        result[:true_airspeed] = (tas_raw * TRUE_AIRSPEED_RESOLUTION).round
      end

      result
    end

    # BDS 6,0: Heading and speed report
    def decode_bds60
      result = { bds: '6,0' }

      # Magnetic heading (bits 1-12)
      if @data[0] == 1
        hdg_sign = @data[1]
        hdg_raw = bits_to_int(@data[2, 10])
        hdg = hdg_raw * HEADING_SCALE
        result[:magnetic_heading] = (hdg_sign == 1 ? 180 + hdg : hdg).round(2)
      end

      # Indicated airspeed (bits 13-23)
      if @data[12] == 1
        ias_raw = bits_to_int(@data[13, 10])
        result[:indicated_airspeed] = ias_raw
      end

      # Mach number (bits 24-34)
      if @data[23] == 1
        mach_raw = bits_to_int(@data[24, 10])
        result[:mach] = (mach_raw * MACH_SCALE).round(3)
      end

      # Barometric altitude rate (bits 35-45)
      if @data[34] == 1
        bar_sign = @data[35]
        bar_raw = bits_to_int(@data[36, 9])
        bar = bar_raw * BARO_RATE_RESOLUTION
        result[:baro_rate] = bar_sign == 1 ? -bar : bar
      end

      # Inertial vertical velocity (bits 46-56)
      if @data[45] == 1
        ivv_sign = @data[46]
        ivv_raw = bits_to_int(@data[47, 9])
        ivv = ivv_raw * BARO_RATE_RESOLUTION
        result[:inertial_vv] = ivv_sign == 1 ? -ivv : ivv
      end

      result
    end

    public

    # Decode aircraft callsign from identification message
    def callsign
      return nil unless adsb? && identification?

      chars = []
      # ME field starts at bit 32, TC is first 5 bits, CA is next 3
      # Characters start at bit 40 (8 characters, 6 bits each)
      me_data = bits_to_int(@raw[32, 56])

      8.times do |i|
        char_idx = (me_data >> (42 - i * 6)) & 0x3F
        chars << CALLSIGN_CHARSET[char_idx]
      end

      chars.join.strip
    end

    # Decode altitude from airborne position message
    def altitude
      return nil unless airborne_position?

      # Altitude is in bits 40-51 of the message (bits 8-19 of ME field)
      alt_bits = @raw[40, 12]

      # Check Q bit (bit 47, which is index 7 in alt_bits)
      q_bit = alt_bits[7]

      if q_bit == 1
        # 25ft resolution - remove Q bit and reconstruct
        n = bits_to_int(alt_bits[0, 7] + alt_bits[8, 4])
        (n * ALTITUDE_25FT_RESOLUTION) - ALTITUDE_OFFSET_25FT
      else
        # 100ft resolution (Gillham encoding)
        decode_gillham_altitude(alt_bits)
      end
    end

    # Get CPR latitude/longitude (needs both even and odd frames for actual position)
    def cpr_position
      return nil unless airborne_position? || surface_position?

      # CPR odd/even flag at bit 53
      odd_flag = @raw[53]

      # Latitude: bits 54-69 (17 bits)
      lat_cpr = bits_to_int(@raw[54, 17])

      # Longitude: bits 71-87 (17 bits)
      lon_cpr = bits_to_int(@raw[71, 17])

      {
        odd: odd_flag == 1,
        lat_cpr: lat_cpr,
        lon_cpr: lon_cpr,
        lat_cpr_norm: lat_cpr / CPR_MAX,
        lon_cpr_norm: lon_cpr / CPR_MAX
      }
    end

    # Decode velocity from airborne velocity message
    def velocity
      return nil unless velocity?

      # Subtype at bits 37-39
      subtype = bits_to_int(@raw[37, 3])

      case subtype
      when 1, 2
        decode_ground_speed_velocity
      when 3, 4
        decode_airspeed_velocity
      end
    end

    private

    def parse_message(bits)
      # Downlink Format (first 5 bits)
      @df = bits_to_int(bits[0, 5])

      if bits.length == LONG_MESSAGE_BITS
        # Long message (DF17, DF20, DF21)
        # Capability (bits 5-7)
        @ca = bits_to_int(bits[5, 3])

        # ICAO address (bits 8-31)
        @icao = format('%06X', bits_to_int(bits[8, 24]))

        # Type code (first 5 bits of ME field, bits 32-36)
        @tc = bits_to_int(bits[32, 5])

        # Store full ME data (56 bits for DF17, or MB field for DF20/21)
        @data = bits[32, 56]
      else
        # Short message (56 bits) - DF4, DF5, DF11
        # Structure: DF(5) + FS(3) + DR(5) + UM(6) + AC/ID(13) + AP(24)
        # Note: ICAO is XOR'd into the CRC, not directly available
        # For now, use CRC syndrome as pseudo-ICAO (won't match real ICAO)
        @ca = bits_to_int(bits[5, 3])  # Flight Status
        @icao = format('%06X', bits_to_int(bits[32, 24]))  # AP field (contains ICAO XOR CRC)
        @tc = nil
        @data = bits[8, 24]  # DR + UM + AC/ID fields
      end
    end

    def verify_crc(bits)
      # Long messages (DF17, DF20, DF21) or short messages (DF4, DF5)
      return false unless [SHORT_MESSAGE_BITS, LONG_MESSAGE_BITS].include?(bits.length)

      # Get DF to determine message type
      df = bits_to_int(bits[0, 5])

      if bits.length == LONG_MESSAGE_BITS
        # Long message - syndrome should be 0
        syndrome = compute_crc24(bits)
        syndrome == 0
      else
        # Short message (56 bits) - CRC contains ICAO XOR'd
        # For now, accept if it parses correctly
        # The ICAO address is recovered from the syndrome
        true
      end
    end

    # Attempt single-bit error correction using CRC syndrome table
    # O(1) lookup instead of O(n) trial-and-error
    def attempt_single_bit_fix
      # Only attempt on long messages (112 bits)
      return false unless @raw.length == LONG_MESSAGE_BITS

      # Build syndrome table on first use
      ADSBDecoder.build_syndrome_table unless ADSBDecoder.syndrome_table

      # Compute the syndrome (CRC of received message)
      syndrome = compute_crc24(@raw)
      return false if syndrome == 0  # No error (shouldn't happen, but check)

      # Look up which bit position produces this syndrome
      bit_pos = ADSBDecoder.syndrome_table[syndrome]
      return false unless bit_pos  # Not a single-bit error

      # Flip the identified bit
      @raw[bit_pos] = @raw[bit_pos] == 1 ? 0 : 1
      @crc_fixed = true
      @error_bit = bit_pos
      true
    end

    # Compute CRC-24 syndrome over all bits
    # For valid DF17 messages, result should be 0
    def compute_crc24(bits)
      crc = 0
      bits.each do |bit|
        msb_out = (crc >> 23) & 1
        crc = ((crc << 1) | bit) & 0xFFFFFF
        crc ^= (CRC24_POLY & 0xFFFFFF) if msb_out == 1
      end
      crc
    end

    def bits_to_int(bits)
      bits.reduce(0) { |acc, bit| (acc << 1) | bit }
    end

    def decode_gillham_altitude(alt_bits)
      # Simplified Gillham decoding for 100ft resolution
      # This is a simplified version - full implementation would need Gray code conversion
      n = bits_to_int(alt_bits)
      (n * ALTITUDE_100FT_RESOLUTION) - ALTITUDE_OFFSET_100FT
    end

    def decode_ground_speed_velocity
      # Direction for Vew (bit 45)
      dew = @raw[45]
      # East-West velocity (bits 46-55)
      vew = bits_to_int(@raw[46, 10]) - 1

      # Direction for Vns (bit 56)
      dns = @raw[56]
      # North-South velocity (bits 57-66)
      vns = bits_to_int(@raw[57, 10]) - 1

      # Calculate actual velocities
      v_ew = dew == 1 ? -vew : vew
      v_ns = dns == 1 ? -vns : vns

      # Ground speed
      speed = Math.sqrt(v_ew**2 + v_ns**2).round

      # Heading (track angle)
      heading = Math.atan2(v_ew, v_ns) * 180 / Math::PI
      heading += 360 if heading < 0

      # Vertical rate
      vr_sign = @raw[68]
      vr_value = bits_to_int(@raw[69, 9])
      vertical_rate = vr_sign == 1 ? -(vr_value - 1) * VERTICAL_RATE_RESOLUTION : (vr_value - 1) * VERTICAL_RATE_RESOLUTION

      {
        speed: speed,
        heading: heading.round(1),
        vertical_rate: vertical_rate,
        type: :ground_speed
      }
    end

    def decode_airspeed_velocity
      # Heading status (bit 45)
      heading_status = @raw[45]
      heading = nil

      if heading_status == 1
        # Heading available (bits 46-55, 10 bits)
        heading_raw = bits_to_int(@raw[46, 10])
        heading = heading_raw * HEADING_RESOLUTION
      end

      # Airspeed type (bit 56): 0 = IAS, 1 = TAS
      airspeed_type = @raw[56]

      # Airspeed (bits 57-66, 10 bits)
      airspeed = bits_to_int(@raw[57, 10])

      # Vertical rate
      vr_sign = @raw[68]
      vr_value = bits_to_int(@raw[69, 9])
      vertical_rate = vr_sign == 1 ? -(vr_value - 1) * VERTICAL_RATE_RESOLUTION : (vr_value - 1) * VERTICAL_RATE_RESOLUTION

      {
        speed: airspeed,
        heading: heading&.round(1),
        vertical_rate: vertical_rate,
        type: airspeed_type == 1 ? :true_airspeed : :indicated_airspeed
      }
    end
  end

  # ICAO Recovery for short messages (DF4, DF5, DF11)
  # Short messages have ICAO XOR'd into the CRC field
  # We recover by trying known ICAOs and checking if CRC validates
  class ICAORecovery
    include ADSB::Constants

    # Compute CRC-24 over bits (returns 24-bit value)
    def self.compute_crc(bits)
      crc = 0
      bits.each do |bit|
        msb_out = (crc >> 23) & 1
        crc = ((crc << 1) | bit) & 0xFFFFFF
        crc ^= (ADSB::Constants::CRC24_POLY & 0xFFFFFF) if msb_out == 1
      end
      crc
    end

    # Attempt to recover ICAO from short message using candidate list
    # Returns recovered ICAO hex string, or nil if not found
    def self.recover(bits, candidates)
      return nil unless bits.length == ADSB::Constants::SHORT_MESSAGE_BITS

      # For short messages:
      # - First 32 bits are data (DF + payload)
      # - Last 24 bits are AP (Address/Parity) = CRC XOR ICAO
      data_bits = bits[0, 32]
      ap_field = bits_to_int(bits[32, 24])

      # Compute CRC over the data portion
      crc = compute_crc(data_bits)

      # The transmitted AP field = CRC XOR ICAO
      # So: ICAO = CRC XOR AP
      # We verify by checking if candidate_icao XOR crc == ap_field

      candidates.each do |candidate|
        icao_int = candidate.to_i(16)
        # If this ICAO is correct, then CRC XOR ICAO should equal AP
        if (crc ^ icao_int) == ap_field
          return candidate
        end
      end

      nil
    end

    def self.bits_to_int(bits)
      bits.reduce(0) { |acc, bit| (acc << 1) | bit }
    end
  end

  # Decode position from even and odd CPR frames
  def self.decode_position(even_msg, odd_msg)
    even_pos = even_msg.cpr_position
    odd_pos = odd_msg.cpr_position

    return nil unless even_pos && odd_pos && !even_pos[:odd] && odd_pos[:odd]

    lat0 = even_pos[:lat_cpr_norm]
    lat1 = odd_pos[:lat_cpr_norm]
    lon0 = even_pos[:lon_cpr_norm]
    lon1 = odd_pos[:lon_cpr_norm]

    # Calculate latitude index
    j = (59 * lat0 - 60 * lat1 + 0.5).floor

    # Calculate latitudes
    lat_even = D_LAT_EVEN * ((j % 60) + lat0)
    lat_odd = D_LAT_ODD * ((j % 59) + lat1)

    lat_even -= 360 if lat_even >= 270
    lat_odd -= 360 if lat_odd >= 270

    # Check if both frames are in the same latitude zone
    nl_even = cpr_nl(lat_even)
    nl_odd = cpr_nl(lat_odd)

    return nil if nl_even != nl_odd

    # Use the most recent message for final position
    # Assuming odd message is more recent
    lat = lat_odd
    nl = nl_odd

    # Calculate longitude
    ni = [nl - 1, 1].max
    m = ((lon0 * (nl - 1) - lon1 * nl + 0.5).floor % ni)
    lon = (360.0 / ni) * (m + lon1)

    lon -= 360 if lon > 180

    { latitude: lat, longitude: lon }
  end

  # Number of longitude zones function
  def self.cpr_nl(lat)
    return 1 if lat.abs >= 87

    nz = 15
    a = 1 - Math.cos(Math::PI / (2 * nz))
    b = Math.cos(Math::PI * lat.abs / 180)**2
    nl = (2 * Math::PI / Math.acos(1 - a / b)).floor

    [[nl, 1].max, 59].min
  end

  def self.decode(bits, options = {})
    Message.new(bits, options)
  end
end
