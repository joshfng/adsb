# frozen_string_literal: true

require "rails_helper"

RSpec.describe SDRReceiver do
  let(:mock_device) { instance_double("RTLSDR::Device") }
  let(:config) { SDRConfig.new(device_index: 0) }

  before do
    # Mock RTLSDR module
    allow(RTLSDR).to receive(:device_count).and_return(1)
    allow(RTLSDR).to receive(:device_name).with(0).and_return("Generic RTL2832U")
    allow(RTLSDR).to receive(:open).with(0).and_return(mock_device)

    # Mock device methods
    allow(mock_device).to receive(:sample_rate=)
    allow(mock_device).to receive(:frequency=)
    allow(mock_device).to receive(:manual_gain_mode!)
    allow(mock_device).to receive(:tuner_gain=)
    allow(mock_device).to receive(:tuner_gain).and_return(496)
    allow(mock_device).to receive(:close)
    allow(mock_device).to receive(:cancel_async)
    allow(mock_device).to receive(:streaming?).and_return(false)
  end

  describe "#initialize" do
    it "creates with default config" do
      receiver = SDRReceiver.new(device_index: 0)
      expect(receiver.running).to be(false)
      expect(receiver.aircraft).to eq({})
      expect(receiver.history).to be_a(FlightHistory)
    end

    it "accepts custom config" do
      custom_config = SDRConfig.new(device_index: 1, gain: 40.0)
      receiver = SDRReceiver.new(config: custom_config)
      expect(receiver.config).to eq(custom_config)
    end

    it "initializes stats" do
      receiver = SDRReceiver.new(config: config)
      stats = receiver.stats
      expect(stats[:messages_total]).to eq(0)
      expect(stats[:messages_position]).to eq(0)
      expect(stats[:sample_rate]).to eq(ADSB::Constants::SAMPLE_RATE_HZ)
    end
  end

  describe "#on_aircraft_update" do
    it "registers callbacks via tracker" do
      receiver = SDRReceiver.new(config: config)
      callback_called = false

      receiver.on_aircraft_update { |_| callback_called = true }

      tracker = receiver.instance_variable_get(:@tracker)
      callbacks = tracker.instance_variable_get(:@callbacks)
      expect(callbacks.length).to eq(1)
    end
  end

  describe "#aircraft_list" do
    it "returns empty array when no aircraft" do
      receiver = SDRReceiver.new(config: config)
      expect(receiver.aircraft_list).to eq([])
    end

    it "delegates to tracker" do
      receiver = SDRReceiver.new(config: config)
      tracker = receiver.instance_variable_get(:@tracker)
      tracker.instance_variable_get(:@aircraft)["A12345"] = {
        icao: "A12345",
        callsign: "UAL123",
        last_seen: Time.now
      }

      list = receiver.aircraft_list
      expect(list.length).to eq(1)
      expect(list.first[:icao]).to eq("A12345")
    end
  end

  describe "#get_stats" do
    it "returns merged stats with demodulator" do
      receiver = SDRReceiver.new(config: config)
      stats = receiver.get_stats

      expect(stats).to include(
        :messages_total,
        :messages_position,
        :uptime_seconds,
        :preambles_detected,
        :crc_failures
      )
    end

    it "calculates uptime when running" do
      receiver = SDRReceiver.new(config: config)
      receiver.instance_variable_get(:@stats)[:start_time] = Time.now - 60

      stats = receiver.get_stats
      expect(stats[:uptime_seconds]).to be >= 59
    end
  end

  describe "private #process_samples" do
    let(:receiver) { SDRReceiver.new(config: config) }

    before do
      # Stub the demodulator to avoid actual signal processing
      demod = receiver.instance_variable_get(:@demodulator)
      allow(demod).to receive(:process_samples).and_return([])
    end

    it "processes empty samples without error" do
      receiver.send(:process_samples, [])
      expect(receiver.stats[:messages_total]).to eq(0)
    end
  end

  describe "private #dump_raw_samples" do
    it "converts complex samples to 8-bit I/Q" do
      # Create a temp file for dump
      require "tempfile"
      dump_file = Tempfile.new([ "dump", ".bin" ])

      begin
        # First create the receiver, then set up its dump file
        receiver = SDRReceiver.new(config: config)
        receiver.instance_variable_set(:@dump_file, File.open(dump_file.path, "wb"))

        # Create test samples
        samples = [
          Complex(0.5, -0.5),   # I=191, Q=63
          Complex(-1.0, 1.0),  # I=0, Q=255
          Complex(0, 0)        # I=127, Q=127
        ]

        receiver.send(:dump_raw_samples, samples)

        # Close to flush
        receiver.instance_variable_get(:@dump_file).close

        # Read and verify
        bytes = File.read(dump_file.path).bytes
        expect(bytes.length).to eq(6) # 3 samples * 2 bytes each
      ensure
        dump_file.close
        dump_file.unlink
      end
    end
  end

  describe "private #apply_snip_filter" do
    let(:receiver) { SDRReceiver.new(config: config) }

    before do
      receiver.config.instance_variable_set(:@snip_level, 0.1)
    end

    it "filters samples below threshold" do
      samples = [
        Complex(0.05, 0.05),  # magnitude ~0.07, below threshold
        Complex(0.2, 0.0),    # magnitude 0.2, above threshold
        Complex(0.01, 0.01)   # magnitude ~0.014, below threshold
      ]

      filtered = receiver.send(:apply_snip_filter, samples)
      expect(filtered.length).to eq(1)
      expect(filtered.first).to eq(Complex(0.2, 0.0))
    end
  end

  describe "TCP connection" do
    it "recognizes TCP config" do
      tcp_config = SDRConfig.new(source_type: :rtl_tcp, rtl_tcp_host: "192.168.1.100", rtl_tcp_port: 5555)
      expect(tcp_config.tcp?).to be(true)
      expect(tcp_config.rtl_tcp_host).to eq("192.168.1.100")
      expect(tcp_config.rtl_tcp_port).to eq(5555)
    end

    it "defaults to non-TCP" do
      regular_config = SDRConfig.new(device_index: 0)
      expect(regular_config.tcp?).to be(false)
    end
  end

  describe "#start and #stop" do
    it "sets running state correctly" do
      allow(mock_device).to receive(:read_samples).and_return([])

      receiver = SDRReceiver.new(config: config)
      expect(receiver.running).to be(false)

      receiver.start
      expect(receiver.running).to be(true)

      receiver.stop
      expect(receiver.running).to be(false)
    end

    it "does not start twice" do
      allow(mock_device).to receive(:read_samples).and_return([])

      receiver = SDRReceiver.new(config: config)
      receiver.start

      # Second start should be no-op
      expect(RTLSDR).to have_received(:open).once
      receiver.start
      expect(RTLSDR).to have_received(:open).once

      receiver.stop
    end
  end
end
