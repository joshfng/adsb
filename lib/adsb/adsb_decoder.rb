# frozen_string_literal: true

require_relative "constants"
require_relative "adsb_message"
require_relative "icao_recovery"

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
    ni = [ nl - 1, 1 ].max
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

    [ [ nl, 1 ].max, 59 ].min
  end

  def self.decode(bits, options = {})
    Message.new(bits, options)
  end
end
