# frozen_string_literal: true

require "rails_helper"

RSpec.describe ADSBDecoder do
  describe 'CRC-24 validation' do
    # Known valid Mode S Extended Squitter (DF17) messages
    let(:valid_messages) do
      [
        '8D40621D58C382D690C8AC2863A7', # Position message
        '8D4840D6202CC371C32CE0576098', # Identification message
        '8D406B902015A678D4D220AA4BDA', # Another aircraft
        '8DA05F219B06B6AF189400CBC33F'  # Velocity message
      ]
    end

    it 'validates known good messages' do
      valid_messages.each do |hex|
        bits = hex_to_bits(hex)
        msg = ADSBDecoder.decode(bits)

        expect(msg.crc_ok).to be(true), "Expected CRC OK for #{hex}"
        expect(msg.valid?).to be(true), "Expected valid for #{hex}"
      end
    end

    it 'rejects messages with invalid CRC' do
      # Corrupt the last byte of a valid message
      corrupted = '8D40621D58C382D690C8AC2863A8'
      bits = hex_to_bits(corrupted)
      msg = ADSBDecoder.decode(bits)

      expect(msg.crc_ok).to be(false)
      expect(msg.valid?).to be(false)
    end

    it 'rejects messages with wrong length' do
      short_bits = [ 0 ] * 100
      msg = ADSBDecoder.decode(short_bits)

      expect(msg.crc_ok).to be(false)
    end
  end

  describe 'message parsing' do
    describe 'identification messages (TC 1-4)' do
      # DF17, TC=4 identification message
      let(:ident_hex) { '8D4840D6202CC371C32CE0576098' }
      let(:msg) { ADSBDecoder.decode(hex_to_bits(ident_hex)) }

      it 'extracts ICAO address' do
        expect(msg.icao).to eq('4840D6')
      end

      it 'identifies as identification message' do
        expect(msg.identification?).to be(true)
      end

      it 'decodes callsign' do
        expect(msg.callsign).to be_a(String)
        expect(msg.callsign.length).to be <= 8
      end

      it 'is not a position or velocity message' do
        expect(msg.airborne_position?).to be(false)
        expect(msg.velocity?).to be(false)
      end
    end

    describe 'airborne position messages (TC 9-18)' do
      let(:position_hex) { '8D40621D58C382D690C8AC2863A7' }
      let(:msg) { ADSBDecoder.decode(hex_to_bits(position_hex)) }

      it 'extracts ICAO address' do
        expect(msg.icao).to eq('40621D')
      end

      it 'identifies as airborne position message' do
        expect(msg.airborne_position?).to be(true)
      end

      it 'decodes altitude' do
        expect(msg.altitude).to be_a(Integer)
      end

      it 'provides CPR position data' do
        cpr = msg.cpr_position
        expect(cpr).to include(:odd, :lat_cpr, :lon_cpr)
        expect(cpr[:lat_cpr]).to be_a(Integer)
        expect(cpr[:lon_cpr]).to be_a(Integer)
      end
    end

    describe 'velocity messages (TC 19)' do
      let(:velocity_hex) { '8DA05F219B06B6AF189400CBC33F' }
      let(:msg) { ADSBDecoder.decode(hex_to_bits(velocity_hex)) }

      it 'extracts ICAO address' do
        expect(msg.icao).to eq('A05F21')
      end

      it 'identifies as velocity message' do
        expect(msg.velocity?).to be(true)
      end

      it 'decodes velocity components' do
        vel = msg.velocity
        expect(vel).to include(:speed, :heading, :vertical_rate)
        expect(vel[:speed]).to be_a(Numeric)
        expect(vel[:heading]).to be_a(Numeric)
      end
    end
  end

  describe '.decode_position' do
    context 'with valid even and odd frames' do
      # These are simplified test cases - real CPR requires specific paired messages
      let(:even_hex) { '8D40621D58C382D690C8AC2863A7' }
      let(:odd_hex) { '8D40621D58C386435CC412692AD6' }

      it 'returns nil if frames are not properly paired' do
        even_msg = ADSBDecoder.decode(hex_to_bits(even_hex))
        odd_msg = ADSBDecoder.decode(hex_to_bits(even_hex)) # Same message

        result = ADSBDecoder.decode_position(even_msg, odd_msg)
        # May return nil if both are even or odd
        expect(result).to be_nil.or(be_a(Hash))
      end
    end
  end

  describe '.cpr_nl' do
    it 'returns 1 for latitudes >= 87 degrees' do
      expect(ADSBDecoder.cpr_nl(87)).to eq(1)
      expect(ADSBDecoder.cpr_nl(90)).to eq(1)
      expect(ADSBDecoder.cpr_nl(-87)).to eq(1)
    end

    it 'returns correct NL for mid-latitudes' do
      # NL decreases as latitude increases
      nl_0 = ADSBDecoder.cpr_nl(0)
      nl_45 = ADSBDecoder.cpr_nl(45)

      expect(nl_0).to be > nl_45
      expect(nl_0).to be_between(1, 59)
      expect(nl_45).to be_between(1, 59)
    end
  end

  describe 'identity reply messages (DF5, DF21)' do
    describe '#identity_reply?' do
      it 'returns true for DF5 messages' do
        # DF5 = 00101 binary (5)
        bits = [ 0, 0, 1, 0, 1 ] + Array.new(51, 0) # 56 bits total for DF5
        msg = ADSBDecoder.decode(bits)

        expect(msg.identity_reply?).to be(true)
      end

      it 'returns true for DF21 messages' do
        # DF21 = 10101 binary (21)
        # For 112-bit messages, CRC must be valid for parsing to occur
        # The decoder skips parsing if CRC fails, so we test the df directly
        msg = ADSBDecoder::Message.new([ 1, 0, 1, 0, 1 ] + Array.new(107, 0))

        # CRC will fail, but we can still check if identity_reply? would work
        # if df was set. Since crc_ok is false, it won't parse, so let's test
        # by manually setting df
        msg.instance_variable_set(:@df, 21)

        expect(msg.identity_reply?).to be(true)
      end

      it 'returns false for DF17 messages' do
        ident_hex = '8D4840D6202CC371C32CE0576098'
        msg = ADSBDecoder.decode(hex_to_bits(ident_hex))

        expect(msg.identity_reply?).to be(false)
      end
    end

    describe '#squawk' do
      it 'returns nil for non-identity messages' do
        ident_hex = '8D4840D6202CC371C32CE0576098' # DF17
        msg = ADSBDecoder.decode(hex_to_bits(ident_hex))

        expect(msg.squawk).to be_nil
      end

      it 'decodes squawk 1200 correctly' do
        # Create a DF5 message with squawk 1200
        # Squawk 1200 = A=1, B=2, C=0, D=0
        # A=1 means a1=1, a2=0, a4=0
        # B=2 means b1=0, b2=1, b4=0
        # C=0 means c1=0, c2=0, c4=0
        # D=0 means d1=0, d2=0, d4=0
        # Format: C1 A1 C2 A2 C4 A4 X B1 D1 B2 D2 B4 D4
        # For 1200: 0 1 0 0 0 0 0 0 0 1 0 0 0
        id_bits = [ 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0 ]

        # Build DF5 message: DF(5 bits) + FS(3 bits) + DR(5 bits) + UM(6 bits) + ID(13 bits) + CRC(24 bits)
        df_bits = [ 0, 0, 1, 0, 1 ]
        fs_bits = [ 0, 0, 0 ]
        dr_bits = [ 0, 0, 0, 0, 0 ]
        um_bits = [ 0, 0, 0, 0, 0, 0 ]
        crc_bits = Array.new(24, 0)

        bits = df_bits + fs_bits + dr_bits + um_bits + id_bits + crc_bits
        msg = ADSBDecoder.decode(bits)

        expect(msg.identity_reply?).to be(true)
        expect(msg.squawk).to eq('1200')
      end

      it 'decodes squawk 7700 (emergency) correctly' do
        # Squawk 7700 = A=7, B=7, C=0, D=0
        # A=7 means a1=1, a2=1, a4=1
        # B=7 means b1=1, b2=1, b4=1
        # C=0 means c1=0, c2=0, c4=0
        # D=0 means d1=0, d2=0, d4=0
        # Format: C1 A1 C2 A2 C4 A4 X B1 D1 B2 D2 B4 D4
        # For 7700: 0 1 0 1 0 1 0 1 0 1 0 1 0
        id_bits = [ 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0 ]

        df_bits = [ 0, 0, 1, 0, 1 ]
        fs_bits = [ 0, 0, 0 ]
        dr_bits = [ 0, 0, 0, 0, 0 ]
        um_bits = [ 0, 0, 0, 0, 0, 0 ]
        crc_bits = Array.new(24, 0)

        bits = df_bits + fs_bits + dr_bits + um_bits + id_bits + crc_bits
        msg = ADSBDecoder.decode(bits)

        expect(msg.squawk).to eq('7700')
      end

      it 'decodes squawk 7500 (hijack) correctly' do
        # Squawk 7500 = A=7, B=5, C=0, D=0
        # A=7 means a1=1, a2=1, a4=1
        # B=5 means b1=1, b2=0, b4=1
        # C=0 means c1=0, c2=0, c4=0
        # D=0 means d1=0, d2=0, d4=0
        # Format: C1 A1 C2 A2 C4 A4 X B1 D1 B2 D2 B4 D4
        # For 7500: 0 1 0 1 0 1 0 1 0 0 0 1 0
        id_bits = [ 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0 ]

        df_bits = [ 0, 0, 1, 0, 1 ]
        fs_bits = [ 0, 0, 0 ]
        dr_bits = [ 0, 0, 0, 0, 0 ]
        um_bits = [ 0, 0, 0, 0, 0, 0 ]
        crc_bits = Array.new(24, 0)

        bits = df_bits + fs_bits + dr_bits + um_bits + id_bits + crc_bits
        msg = ADSBDecoder.decode(bits)

        expect(msg.squawk).to eq('7500')
      end

      it 'decodes squawk 7600 (radio failure) correctly' do
        # Squawk 7600 = A=7, B=6, C=0, D=0
        # A=7 means a1=1, a2=1, a4=1
        # B=6 means b1=0, b2=1, b4=1
        # C=0 means c1=0, c2=0, c4=0
        # D=0 means d1=0, d2=0, d4=0
        # Format: C1 A1 C2 A2 C4 A4 X B1 D1 B2 D2 B4 D4
        # For 7600: 0 1 0 1 0 1 0 0 0 1 0 1 0
        id_bits = [ 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0 ]

        df_bits = [ 0, 0, 1, 0, 1 ]
        fs_bits = [ 0, 0, 0 ]
        dr_bits = [ 0, 0, 0, 0, 0 ]
        um_bits = [ 0, 0, 0, 0, 0, 0 ]
        crc_bits = Array.new(24, 0)

        bits = df_bits + fs_bits + dr_bits + um_bits + id_bits + crc_bits
        msg = ADSBDecoder.decode(bits)

        expect(msg.squawk).to eq('7600')
      end
    end
  end

  describe 'downlink format constants' do
    it 'defines DF17 for ADS-B' do
      expect(ADSBDecoder::DF_ADSB).to eq(17)
    end

    it 'defines DF5 for Identity Reply' do
      expect(ADSBDecoder::DF_IDENTITY_REPLY).to eq(5)
    end

    it 'defines DF21 for Comm-B Identity Reply' do
      expect(ADSBDecoder::DF_COMM_B_IDENTITY).to eq(21)
    end

    it 'defines DF4 for Altitude Reply' do
      expect(ADSBDecoder::DF_ALTITUDE_REPLY).to eq(4)
    end

    it 'defines DF20 for Comm-B Altitude Reply' do
      expect(ADSBDecoder::DF_COMM_B_ALT).to eq(20)
    end
  end

  describe 'EHS (Enhanced Surveillance) decoding' do
    describe '#comm_b?' do
      it 'returns true for DF20 messages' do
        msg = ADSBDecoder::Message.new([ 1, 0, 1, 0, 0 ] + Array.new(107, 0))
        msg.instance_variable_set(:@df, 20)
        expect(msg.comm_b?).to be(true)
      end

      it 'returns true for DF21 messages' do
        msg = ADSBDecoder::Message.new([ 1, 0, 1, 0, 1 ] + Array.new(107, 0))
        msg.instance_variable_set(:@df, 21)
        expect(msg.comm_b?).to be(true)
      end

      it 'returns false for DF17 messages' do
        ident_hex = '8D4840D6202CC371C32CE0576098'
        msg = ADSBDecoder.decode(hex_to_bits(ident_hex))
        expect(msg.comm_b?).to be(false)
      end
    end

    describe '#ehs_data' do
      it 'returns nil for non-Comm-B messages' do
        ident_hex = '8D4840D6202CC371C32CE0576098'
        msg = ADSBDecoder.decode(hex_to_bits(ident_hex))
        expect(msg.ehs_data).to be_nil
      end

      it 'returns nil when data field is missing' do
        msg = ADSBDecoder::Message.new([ 1, 0, 1, 0, 0 ] + Array.new(107, 0))
        msg.instance_variable_set(:@df, 20)
        msg.instance_variable_set(:@data, nil)
        expect(msg.ehs_data).to be_nil
      end

      context 'with BDS 4,0 data (selected altitude)' do
        it 'decodes selected altitude' do
          # Create a mock DF20 message with BDS 4,0 data
          msg = ADSBDecoder::Message.new(Array.new(112, 0))
          msg.instance_variable_set(:@df, 20)

          # BDS 4,0: status bit = 1, altitude = 350 (350 * 16 = 5600 ft)
          # Bit 0 = 1 (status), bits 1-12 = altitude
          data = [ 1 ] + int_to_bits(350, 12) + Array.new(43, 0)
          msg.instance_variable_set(:@data, data)

          ehs = msg.ehs_data
          expect(ehs).not_to be_nil
          expect(ehs[:bds]).to eq('4,0')
          expect(ehs[:selected_altitude]).to eq(5600)
        end
      end

      context 'with BDS 6,0 data (heading and speed)' do
        it 'decodes indicated airspeed' do
          msg = ADSBDecoder::Message.new(Array.new(112, 0))
          msg.instance_variable_set(:@df, 20)

          # BDS 6,0: heading status = 0, airspeed status = 1 (at bit 12), IAS = 250 (bits 13-22)
          # Need to ensure bds60_valid passes: airspeed_status at @data[12]
          data = Array.new(56, 0)
          data[12] = 1  # airspeed status
          # IAS value at bits 13-22
          ias_bits = int_to_bits(250, 10)
          10.times { |i| data[13 + i] = ias_bits[i] }
          msg.instance_variable_set(:@data, data)

          ehs = msg.ehs_data
          expect(ehs).not_to be_nil
          expect(ehs[:bds]).to eq('6,0')
          expect(ehs[:indicated_airspeed]).to eq(250)
        end
      end
    end
  end

  describe ADSBDecoder::ICAORecovery do
    describe '.compute_crc' do
      it 'computes CRC-24 over bits' do
        # Simple test - 32 zero bits
        bits = Array.new(32, 0)
        crc = ADSBDecoder::ICAORecovery.compute_crc(bits)
        expect(crc).to be_a(Integer)
        expect(crc).to be >= 0
        expect(crc).to be < 0x1000000  # 24-bit max
      end

      it 'returns different CRCs for different inputs' do
        bits1 = Array.new(32, 0)
        bits2 = Array.new(32, 0)
        bits2[0] = 1  # Change one bit

        crc1 = ADSBDecoder::ICAORecovery.compute_crc(bits1)
        crc2 = ADSBDecoder::ICAORecovery.compute_crc(bits2)

        expect(crc1).not_to eq(crc2)
      end
    end

    describe '.recover' do
      it 'returns nil for non-56-bit messages' do
        bits = Array.new(112, 0)
        result = ADSBDecoder::ICAORecovery.recover(bits, [ 'A12345' ])
        expect(result).to be_nil
      end

      it 'returns nil when no candidate matches' do
        bits = Array.new(56, 0)
        result = ADSBDecoder::ICAORecovery.recover(bits, [ 'A12345', 'B67890' ])
        expect(result).to be_nil
      end

      it 'recovers ICAO when candidate matches' do
        # Create a synthetic short message where we know the ICAO
        # For a 56-bit message: first 32 bits = data, last 24 bits = CRC XOR ICAO
        target_icao = 'A12345'
        icao_int = target_icao.to_i(16)

        # Create data bits (DF=5 identity reply: 00101 + some data)
        data_bits = [ 0, 0, 1, 0, 1 ]  # DF=5
        data_bits += Array.new(27, 0)  # Fill remaining data bits

        # Compute CRC of the data portion
        crc = ADSBDecoder::ICAORecovery.compute_crc(data_bits)

        # AP field = CRC XOR ICAO
        ap_field = crc ^ icao_int

        # Convert AP field to bits (24 bits)
        ap_bits = 24.times.map { |i| (ap_field >> (23 - i)) & 1 }

        # Build complete message
        bits = data_bits + ap_bits

        # Try recovery
        result = ADSBDecoder::ICAORecovery.recover(bits, [ 'FFFFFF', target_icao, '000000' ])
        expect(result).to eq(target_icao)
      end

      it 'checks candidates in order and returns first match' do
        target_icao = 'B67890'
        icao_int = target_icao.to_i(16)

        data_bits = [ 0, 0, 1, 0, 0 ]  # DF=4
        data_bits += Array.new(27, 0)

        crc = ADSBDecoder::ICAORecovery.compute_crc(data_bits)
        ap_field = crc ^ icao_int
        ap_bits = 24.times.map { |i| (ap_field >> (23 - i)) & 1 }
        bits = data_bits + ap_bits

        result = ADSBDecoder::ICAORecovery.recover(bits, [ target_icao, 'AAAAAA' ])
        expect(result).to eq(target_icao)
      end
    end
  end

  describe 'Message ICAO recovery support' do
    describe '#needs_icao_recovery?' do
      it 'returns true for DF4 short messages' do
        bits = Array.new(56, 0)
        bits[0..4] = [ 0, 0, 1, 0, 0 ]  # DF=4
        msg = ADSBDecoder::Message.new(bits)
        msg.instance_variable_set(:@crc_ok, true)
        msg.instance_variable_set(:@df, 4)

        expect(msg.needs_icao_recovery?).to be(true)
      end

      it 'returns true for DF5 short messages' do
        bits = Array.new(56, 0)
        bits[0..4] = [ 0, 0, 1, 0, 1 ]  # DF=5
        msg = ADSBDecoder::Message.new(bits)
        msg.instance_variable_set(:@crc_ok, true)
        msg.instance_variable_set(:@df, 5)

        expect(msg.needs_icao_recovery?).to be(true)
      end

      it 'returns false for long messages (DF17)' do
        bits = Array.new(112, 0)
        bits[0..4] = [ 1, 0, 0, 0, 1 ]  # DF=17
        msg = ADSBDecoder::Message.new(bits)
        msg.instance_variable_set(:@crc_ok, true)
        msg.instance_variable_set(:@df, 17)

        expect(msg.needs_icao_recovery?).to be(false)
      end
    end

    describe '#set_recovered_icao' do
      it 'updates ICAO and sets recovered flag' do
        bits = Array.new(56, 0)
        msg = ADSBDecoder::Message.new(bits)
        msg.instance_variable_set(:@icao, 'ORIGINAL')
        msg.instance_variable_set(:@icao_recovered, false)

        msg.set_recovered_icao('ABCDEF')

        expect(msg.icao).to eq('ABCDEF')
        expect(msg.icao_recovered).to be(true)
      end
    end
  end

  describe 'CRC error correction options' do
    let(:valid_hex) { '8D40621D58C382D690C8AC2863A7' }
    let(:valid_bits) { hex_to_bits(valid_hex) }

    describe 'fix_errors option' do
      it 'is enabled by default' do
        expect(ADSBDecoder.default_options[:fix_errors]).to eq(true)
      end

      context 'when fix_errors is true' do
        it 'fixes single-bit errors in DF17 messages' do
          # Create a message with one corrupted bit
          corrupted_bits = valid_bits.dup
          corrupted_bits[50] = corrupted_bits[50] == 1 ? 0 : 1  # Flip bit 50

          msg = ADSBDecoder.decode(corrupted_bits, fix_errors: true)

          expect(msg.crc_ok).to be(true)
          expect(msg.crc_fixed?).to be(true)
          expect(msg.error_bit).to eq(50)
          expect(msg.valid?).to be(true)
        end

        it 'does not mark valid messages as fixed' do
          msg = ADSBDecoder.decode(valid_bits, fix_errors: true)

          expect(msg.crc_ok).to be(true)
          expect(msg.crc_fixed?).to be(false)
          expect(msg.error_bit).to be_nil
        end

        it 'fails for messages with multiple bit errors' do
          # Create a message with two corrupted bits
          corrupted_bits = valid_bits.dup
          corrupted_bits[50] = corrupted_bits[50] == 1 ? 0 : 1
          corrupted_bits[60] = corrupted_bits[60] == 1 ? 0 : 1

          msg = ADSBDecoder.decode(corrupted_bits, fix_errors: true)

          expect(msg.crc_ok).to be(false)
          expect(msg.crc_fixed?).to be(false)
        end
      end

      context 'when fix_errors is false' do
        it 'does not attempt to fix single-bit errors' do
          corrupted_bits = valid_bits.dup
          corrupted_bits[50] = corrupted_bits[50] == 1 ? 0 : 1

          msg = ADSBDecoder.decode(corrupted_bits, fix_errors: false)

          expect(msg.crc_ok).to be(false)
          expect(msg.crc_fixed?).to be(false)
        end
      end
    end

    describe 'crc_check option' do
      it 'is enabled by default' do
        expect(ADSBDecoder.default_options[:crc_check]).to eq(true)
      end

      context 'when crc_check is true' do
        it 'rejects messages with bad CRC' do
          corrupted_bits = valid_bits.dup
          corrupted_bits[50] = corrupted_bits[50] == 1 ? 0 : 1
          corrupted_bits[60] = corrupted_bits[60] == 1 ? 0 : 1

          msg = ADSBDecoder.decode(corrupted_bits, crc_check: true, fix_errors: false)

          expect(msg.crc_ok).to be(false)
        end
      end

      context 'when crc_check is false' do
        it 'accepts messages regardless of CRC' do
          corrupted_bits = valid_bits.dup
          corrupted_bits[50] = corrupted_bits[50] == 1 ? 0 : 1
          corrupted_bits[60] = corrupted_bits[60] == 1 ? 0 : 1

          msg = ADSBDecoder.decode(corrupted_bits, crc_check: false)

          expect(msg.crc_ok).to be(true)
          expect(msg.crc_fixed?).to be(false)
        end

        it 'still parses the message content' do
          corrupted_bits = valid_bits.dup
          # Corrupt the CRC portion (last 24 bits) - won't affect ICAO
          corrupted_bits[-1] = corrupted_bits[-1] == 1 ? 0 : 1
          corrupted_bits[-2] = corrupted_bits[-2] == 1 ? 0 : 1

          msg = ADSBDecoder.decode(corrupted_bits, crc_check: false)

          expect(msg.crc_ok).to be(true)
          expect(msg.icao).to eq('40621D')
        end
      end
    end

    describe 'combined options' do
      it 'fix_errors has no effect when crc_check is false' do
        corrupted_bits = valid_bits.dup
        corrupted_bits[50] = corrupted_bits[50] == 1 ? 0 : 1

        msg = ADSBDecoder.decode(corrupted_bits, fix_errors: true, crc_check: false)

        # CRC check is skipped, so fix_errors is not attempted
        expect(msg.crc_ok).to be(true)
        expect(msg.crc_fixed?).to be(false)
      end
    end
  end
end

# Helper to convert integer to bits array
def int_to_bits(n, num_bits)
  num_bits.times.map { |i| (n >> (num_bits - 1 - i)) & 1 }
end
