# frozen_string_literal: true

require_relative "constants"

# ICAO Recovery for short messages (DF4, DF5, DF11)
# Short messages have ICAO XOR'd into the CRC field
# We recover by trying known ICAOs and checking if CRC validates
module ADSBDecoder
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
end
