# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SDRConfig do
  describe '#initialize' do
    it 'uses default values when no options provided' do
      config = SDRConfig.new

      expect(config.device_index).to eq(0)
      expect(config.gain).to eq(:max)
      expect(config.frequency).to eq(1_090_000_000)
      expect(config.receiver_lat).to be_nil
      expect(config.receiver_lon).to be_nil
      expect(config.max_range_nm).to eq(300)
      expect(config.fix_errors).to eq(true)
      expect(config.crc_check).to eq(true)
      expect(config.show_only).to be_nil
      expect(config.snip_level).to be_nil
      expect(config.dump_raw).to be_nil
    end

    it 'accepts custom options' do
      config = SDRConfig.new(
        device_index: 1,
        gain: 40.0,
        frequency: 978_000_000,
        receiver_lat: 40.0,
        receiver_lon: -81.0,
        max_range_nm: 200,
        fix_errors: false,
        crc_check: false,
        show_only: 'A12345',
        snip_level: 0.01,
        dump_raw: '/tmp/test.bin'
      )

      expect(config.device_index).to eq(1)
      expect(config.gain).to eq(40.0)
      expect(config.frequency).to eq(978_000_000)
      expect(config.receiver_lat).to eq(40.0)
      expect(config.receiver_lon).to eq(-81.0)
      expect(config.max_range_nm).to eq(200)
      expect(config.fix_errors).to eq(false)
      expect(config.crc_check).to eq(false)
      expect(config.show_only).to eq('A12345')
      expect(config.snip_level).to eq(0.01)
      expect(config.dump_raw).to eq('/tmp/test.bin')
    end
  end

  describe '#gain_tenths_db' do
    it 'returns DEFAULT_GAIN_TENTHS_DB for :max' do
      config = SDRConfig.new(gain: :max)
      expect(config.gain_tenths_db).to eq(ADSB::Constants::DEFAULT_GAIN_TENTHS_DB)
    end

    it 'converts dB to tenths of dB' do
      config = SDRConfig.new(gain: 40.0)
      expect(config.gain_tenths_db).to eq(400)

      config = SDRConfig.new(gain: 49.6)
      expect(config.gain_tenths_db).to eq(496)
    end
  end

  describe '#has_receiver_position?' do
    it 'returns true when both lat and lon are set' do
      config = SDRConfig.new(receiver_lat: 40.0, receiver_lon: -81.0)
      expect(config.has_receiver_position?).to eq(true)
    end

    it 'returns false when only lat is set' do
      config = SDRConfig.new(receiver_lat: 40.0)
      expect(config.has_receiver_position?).to eq(false)
    end

    it 'returns false when only lon is set' do
      config = SDRConfig.new(receiver_lon: -81.0)
      expect(config.has_receiver_position?).to eq(false)
    end

    it 'returns false when neither is set' do
      config = SDRConfig.new
      expect(config.has_receiver_position?).to eq(false)
    end
  end

  describe '#to_h' do
    it 'returns hash with all options' do
      config = SDRConfig.new(device_index: 1, gain: 40.0)
      hash = config.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:device_index]).to eq(1)
      expect(hash[:gain]).to eq(40.0)
      expect(hash.keys).to include(
        :device_index, :gain, :frequency,
        :receiver_lat, :receiver_lon, :max_range_nm,
        :fix_errors, :crc_check, :show_only,
        :snip_level, :dump_raw
      )
    end
  end

  describe '.from_env' do
    before do
      # Clear relevant env vars
      %w[
        ADSB_DEVICE_INDEX ADSB_GAIN ADSB_FREQUENCY
        ADSB_LAT ADSB_LON ADSB_MAX_RANGE ADSB_NO_FIX ADSB_NO_CRC_CHECK
        ADSB_SHOW_ONLY ADSB_SNIP ADSB_DUMP_RAW
      ].each { |k| ENV.delete(k) }
    end

    it 'uses defaults when no env vars set' do
      config = SDRConfig.from_env

      expect(config.device_index).to eq(0)
      expect(config.gain).to eq(:max)
      expect(config.fix_errors).to eq(true)
      expect(config.crc_check).to eq(true)
    end

    it 'reads device index from env' do
      ENV['ADSB_DEVICE_INDEX'] = '2'
      config = SDRConfig.from_env
      expect(config.device_index).to eq(2)
    end

    it 'reads gain from env' do
      ENV['ADSB_GAIN'] = '40.0'
      config = SDRConfig.from_env
      expect(config.gain).to eq(40.0)
    end

    it 'reads frequency from env' do
      ENV['ADSB_FREQUENCY'] = '978000000'
      config = SDRConfig.from_env
      expect(config.frequency).to eq(978_000_000)
    end

    it 'reads receiver position from env' do
      ENV['ADSB_LAT'] = '40.5'
      ENV['ADSB_LON'] = '-81.2'
      config = SDRConfig.from_env
      expect(config.receiver_lat).to eq(40.5)
      expect(config.receiver_lon).to eq(-81.2)
    end

    it 'reads max_range from env' do
      ENV['ADSB_MAX_RANGE'] = '200'
      config = SDRConfig.from_env
      expect(config.max_range_nm).to eq(200)
    end

    it 'reads fix_errors (inverted) from env' do
      ENV['ADSB_NO_FIX'] = '1'
      config = SDRConfig.from_env
      expect(config.fix_errors).to eq(false)
    end

    it 'reads crc_check (inverted) from env' do
      ENV['ADSB_NO_CRC_CHECK'] = '1'
      config = SDRConfig.from_env
      expect(config.crc_check).to eq(false)
    end

    it 'reads show_only from env and uppercases' do
      ENV['ADSB_SHOW_ONLY'] = 'a12345'
      config = SDRConfig.from_env
      expect(config.show_only).to eq('A12345')
    end

    it 'reads snip_level from env' do
      ENV['ADSB_SNIP'] = '0.01'
      config = SDRConfig.from_env
      expect(config.snip_level).to eq(0.01)
    end

    it 'reads dump_raw from env' do
      ENV['ADSB_DUMP_RAW'] = '/tmp/test.bin'
      config = SDRConfig.from_env
      expect(config.dump_raw).to eq('/tmp/test.bin')
    end
  end

  describe '.parse_gain' do
    it 'returns :max for nil' do
      expect(SDRConfig.parse_gain(nil)).to eq(:max)
    end

    it 'returns :max for empty string' do
      expect(SDRConfig.parse_gain('')).to eq(:max)
    end

    it 'returns float for other values' do
      expect(SDRConfig.parse_gain('40')).to eq(40.0)
      expect(SDRConfig.parse_gain('49.6')).to eq(49.6)
    end
  end
end
