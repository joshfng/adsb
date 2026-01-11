# frozen_string_literal: true

require "rails_helper"

RSpec.describe AircraftTracker do
  let(:config) { SDRConfig.new(device_index: 0) }
  let(:tracker) { AircraftTracker.new(config: config) }

  describe "#initialize" do
    it "creates with empty aircraft hash" do
      expect(tracker.aircraft).to eq({})
    end

    it "creates FlightHistory" do
      expect(tracker.history).to be_a(FlightHistory)
    end

    it "initializes stats" do
      stats = tracker.get_stats
      expect(stats[:messages_total]).to eq(0)
      expect(stats[:messages_position]).to eq(0)
    end
  end

  describe "#on_aircraft_update" do
    it "registers callbacks" do
      callback_called = false

      tracker.on_aircraft_update { |_| callback_called = true }

      callbacks = tracker.instance_variable_get(:@callbacks)
      expect(callbacks.length).to eq(1)
    end
  end

  describe "#aircraft_list" do
    it "returns empty array when no aircraft" do
      expect(tracker.aircraft_list).to eq([])
    end

    it "returns tracked aircraft" do
      aircraft_hash = tracker.instance_variable_get(:@aircraft)
      aircraft_hash["A12345"] = {
        icao: "A12345",
        callsign: "UAL123",
        last_seen: Time.now
      }

      list = tracker.aircraft_list
      expect(list.length).to eq(1)
      expect(list.first[:icao]).to eq("A12345")
    end

    it "removes stale aircraft" do
      aircraft_hash = tracker.instance_variable_get(:@aircraft)
      aircraft_hash["STALE1"] = {
        icao: "STALE1",
        last_seen: Time.now - 120 # 2 minutes ago
      }

      list = tracker.aircraft_list
      expect(list).to be_empty
    end
  end

  describe "private #calculate_distance" do
    it "calculates haversine distance correctly" do
      # Known distance: LAX to SFO is ~337nm
      lax_lat, lax_lon = 33.9425, -118.4081
      sfo_lat, sfo_lon = 37.6213, -122.3790

      distance = tracker.send(:calculate_distance, lax_lat, lax_lon, sfo_lat, sfo_lon)
      expect(distance).to be_within(5).of(298) # Approximately 298nm
    end

    it "returns 0 for same point" do
      distance = tracker.send(:calculate_distance, 40.0, -74.0, 40.0, -74.0)
      expect(distance).to eq(0)
    end
  end

  describe "private #notify_callbacks" do
    it "calls all registered callbacks" do
      results = []

      tracker.on_aircraft_update { |data| results << data[:icao] }
      tracker.on_aircraft_update { |data| results << data[:callsign] }

      aircraft_data = { icao: "ABC123", callsign: "TEST", last_seen: Time.now }
      tracker.send(:notify_callbacks, aircraft_data)

      expect(results).to eq([ "ABC123", "TEST" ])
    end

    it "continues after callback error" do
      results = []

      tracker.on_aircraft_update { raise "Error!" }
      tracker.on_aircraft_update { |data| results << data[:icao] }

      aircraft_data = { icao: "ABC123", last_seen: Time.now }
      tracker.send(:notify_callbacks, aircraft_data)

      expect(results).to eq([ "ABC123" ])
    end

    it "excludes internal position tracking data" do
      received_data = nil

      tracker.on_aircraft_update { |data| received_data = data }

      aircraft_data = {
        icao: "ABC123",
        even_position: { msg: "even" },
        odd_position: { msg: "odd" },
        last_seen: Time.now
      }
      tracker.send(:notify_callbacks, aircraft_data)

      expect(received_data).not_to have_key(:even_position)
      expect(received_data).not_to have_key(:odd_position)
      expect(received_data[:icao]).to eq("ABC123")
    end
  end

  describe "private #try_decode_position" do
    it "returns nil when missing even frame" do
      aircraft = { odd_position: { msg: double, time: Time.now } }
      result = tracker.send(:try_decode_position, aircraft)
      expect(result).to be_nil
    end

    it "returns nil when missing odd frame" do
      aircraft = { even_position: { msg: double, time: Time.now } }
      result = tracker.send(:try_decode_position, aircraft)
      expect(result).to be_nil
    end

    it "returns nil when frames too old" do
      aircraft = {
        even_position: { msg: double, time: Time.now - 20 },
        odd_position: { msg: double, time: Time.now }
      }
      result = tracker.send(:try_decode_position, aircraft)
      expect(result).to be_nil
    end
  end

  describe "private #save_to_history" do
    it "throttles saves per aircraft" do
      history = tracker.history

      allow(history).to receive(:record_aircraft)
      allow(history).to receive(:record_sighting)

      aircraft = { icao: "ABC123", callsign: "TEST" }

      # First save should go through
      tracker.send(:save_to_history, aircraft)
      expect(history).to have_received(:record_aircraft).once

      # Second save immediately should be throttled
      tracker.send(:save_to_history, aircraft)
      expect(history).to have_received(:record_aircraft).once
    end
  end

  describe "private #update_aircraft" do
    def create_mock_message(type:, icao: "A12345", crc_fixed: false)
      msg = instance_double("ADSBDecoder::Message")
      allow(msg).to receive(:icao).and_return(icao)
      allow(msg).to receive(:crc_fixed?).and_return(crc_fixed)
      allow(msg).to receive(:signal_strength).and_return(0.05)
      allow(msg).to receive(:identification?).and_return(type == :identification)
      allow(msg).to receive(:airborne_position?).and_return(type == :position)
      allow(msg).to receive(:surface_position?).and_return(false)
      allow(msg).to receive(:velocity?).and_return(type == :velocity)
      allow(msg).to receive(:identity_reply?).and_return(type == :squawk)
      allow(msg).to receive(:comm_b?).and_return(false)
      allow(msg).to receive(:callsign).and_return("UAL123") if type == :identification
      allow(msg).to receive(:altitude).and_return(35000) if type == :position
      allow(msg).to receive(:cpr_position).and_return(nil)
      allow(msg).to receive(:velocity).and_return({ speed: 450, heading: 90, vertical_rate: 0 }) if type == :velocity
      allow(msg).to receive(:squawk).and_return("1200") if type == :squawk
      msg
    end

    it "creates new aircraft entry" do
      msg = create_mock_message(type: :identification)
      tracker.send(:update_aircraft, msg)

      aircraft = tracker.aircraft["A12345"]
      expect(aircraft).not_to be_nil
      expect(aircraft[:icao]).to eq("A12345")
      expect(aircraft[:callsign]).to eq("UAL123")
    end

    it "updates identification message stats" do
      msg = create_mock_message(type: :identification)
      tracker.send(:update_aircraft, msg)

      expect(tracker.get_stats[:messages_identification]).to eq(1)
    end

    it "updates position message stats" do
      msg = create_mock_message(type: :position)
      tracker.send(:update_aircraft, msg)

      expect(tracker.get_stats[:messages_position]).to eq(1)
    end

    it "updates velocity message stats" do
      msg = create_mock_message(type: :velocity)
      tracker.send(:update_aircraft, msg)

      expect(tracker.get_stats[:messages_velocity]).to eq(1)
      aircraft = tracker.aircraft["A12345"]
      expect(aircraft[:speed]).to eq(450)
      expect(aircraft[:heading]).to eq(90)
    end

    it "updates squawk from identity reply" do
      msg = create_mock_message(type: :squawk)
      tracker.send(:update_aircraft, msg)

      expect(tracker.get_stats[:messages_squawk]).to eq(1)
      aircraft = tracker.aircraft["A12345"]
      expect(aircraft[:squawk]).to eq("1200")
    end

    it "calculates exponential moving average for signal strength" do
      msg1 = create_mock_message(type: :identification)
      allow(msg1).to receive(:signal_strength).and_return(0.1)
      tracker.send(:update_aircraft, msg1)

      aircraft = tracker.aircraft["A12345"]
      expect(aircraft[:signal_strength]).to eq(0.1)

      msg2 = create_mock_message(type: :identification)
      allow(msg2).to receive(:signal_strength).and_return(0.2)
      tracker.send(:update_aircraft, msg2)

      # EMA: 0.1 * 0.7 + 0.2 * 0.3 = 0.07 + 0.06 = 0.13
      expect(aircraft[:signal_strength]).to be_within(0.01).of(0.13)
    end
  end

  describe "private #refresh_icao_candidates" do
    it "collects in-memory aircraft ICAOs" do
      tracker.instance_variable_get(:@aircraft)["ABC123"] = { icao: "ABC123" }
      tracker.send(:refresh_icao_candidates)

      candidates = tracker.instance_variable_get(:@icao_candidates)
      expect(candidates).to include("ABC123")
    end
  end

  describe "private #attempt_icao_recovery" do
    it "returns nil when no candidates match" do
      msg = instance_double("ADSBDecoder::Message")
      allow(msg).to receive(:raw).and_return(Array.new(56, 0))

      result = tracker.send(:attempt_icao_recovery, msg)
      expect(result).to be_nil
    end
  end
end
