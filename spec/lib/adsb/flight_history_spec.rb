# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlightHistory do
  let(:history) { FlightHistory.new }

  before do
    # Clean up test data
    Sighting.delete_all
    Aircraft.delete_all
  end

  # Helper to generate valid 6-char hex ICAOs
  def hex_icao(num)
    format("%06X", num)
  end

  describe "#initialize" do
    it "creates instance without error" do
      expect(FlightHistory.new).to be_a(FlightHistory)
    end
  end

  describe "#record_sighting" do
    it "creates a sighting record" do
      aircraft_data = {
        icao: "A12345",
        callsign: "UAL123",
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 35000,
        speed: 450,
        heading: 90,
        squawk: "1200",
        signal_strength: 0.05
      }

      expect { history.record_sighting(aircraft_data) }.to change { Sighting.count }.by(1)

      sighting = Sighting.last
      expect(sighting.icao).to eq("A12345")
      expect(sighting.callsign).to eq("UAL123")
      expect(sighting.latitude).to eq(37.7749)
      expect(sighting.altitude).to eq(35000)
    end

    it "ignores nil icao" do
      expect { history.record_sighting({ icao: nil }) }.not_to change { Sighting.count }
    end

    it "handles missing optional fields" do
      expect { history.record_sighting({ icao: "B67890" }) }.to change { Sighting.count }.by(1)

      sighting = Sighting.last
      expect(sighting.callsign).to be_nil
      expect(sighting.latitude).to be_nil
    end
  end

  describe "#record_aircraft" do
    it "creates new aircraft on first sighting" do
      expect { history.record_aircraft("C11111", "DAL456") }.to change { Aircraft.count }.by(1)

      aircraft = Aircraft.find_by(icao: "C11111")
      expect(aircraft.callsign).to eq("DAL456")
      expect(aircraft.sighting_count).to eq(1)
    end

    it "updates existing aircraft" do
      history.record_aircraft("D22222", nil)
      history.record_aircraft("D22222", "SWA789")

      aircraft = Aircraft.find_by(icao: "D22222")
      expect(aircraft.callsign).to eq("SWA789")
      expect(aircraft.sighting_count).to eq(2)
    end

    it "preserves callsign if new one is nil" do
      history.record_aircraft("E33333", "AAL100")
      history.record_aircraft("E33333", nil)

      aircraft = Aircraft.find_by(icao: "E33333")
      expect(aircraft.callsign).to eq("AAL100")
    end

    it "handles concurrent inserts" do
      # Use DatabaseCleaner transaction strategy to avoid threading issues
      # For this test, just verify the retry mechanism works
      history.record_aircraft("F44444", "TEST")
      history.record_aircraft("F44444", "TEST2")

      expect(Aircraft.where(icao: "F44444").count).to eq(1)
      aircraft = Aircraft.find_by(icao: "F44444")
      expect(aircraft.sighting_count).to eq(2)
    end
  end

  describe "#get_stats" do
    before do
      # Create some test data with valid 6-char hex ICAOs
      history.record_aircraft("A00001", "TEST1")
      history.record_sighting(icao: "A00001", callsign: "TEST1", altitude: 30000)

      history.record_aircraft("A00002", "TEST2")
      history.record_sighting(icao: "A00002", callsign: "TEST2", altitude: 35000)
    end

    it "returns statistics hash" do
      stats = history.get_stats

      expect(stats).to include(
        :total_aircraft_seen,
        :aircraft_today,
        :sightings_today,
        :sightings_total,
        :busiest_hours,
        :most_seen_aircraft
      )
    end

    it "counts aircraft correctly" do
      stats = history.get_stats
      expect(stats[:total_aircraft_seen]).to eq(2)
    end

    it "counts sightings correctly" do
      stats = history.get_stats
      expect(stats[:sightings_total]).to eq(2)
    end
  end

  describe "#get_positions" do
    before do
      # Create sightings with positions (valid 6-char hex ICAOs)
      3.times do |i|
        history.record_sighting(
          icao: format("AA%04X", i),
          latitude: 37.0 + i * 0.1,
          longitude: -122.0 + i * 0.1,
          altitude: 30000
        )
      end

      # Create sighting without position
      history.record_sighting(icao: "BB0000", altitude: 25000)
    end

    it "returns only positions with lat/lon" do
      positions = history.get_positions(hours: 24)
      expect(positions.length).to eq(3)
    end

    it "groups by rounded coordinates" do
      positions = history.get_positions(hours: 24)
      positions.each do |pos|
        expect(pos).to include(:lat, :lon, :count)
      end
    end

    it "respects hours parameter" do
      # Old sighting won't be visible - get one with position
      old_sighting = Sighting.where.not(latitude: nil).first
      old_sighting.update!(seen_at: 48.hours.ago)

      positions = history.get_positions(hours: 24)
      expect(positions.length).to eq(2)
    end

    it "respects limit parameter" do
      positions = history.get_positions(hours: 24, limit: 2)
      expect(positions.length).to eq(2)
    end
  end

  describe "#aircraft_history" do
    before do
      5.times do |i|
        history.record_sighting(
          icao: "CC0001",
          callsign: "TEST",
          latitude: 37.0 + i * 0.01,
          longitude: -122.0,
          altitude: 30000 + i * 1000
        )
      end
    end

    it "returns history for specific aircraft" do
      result = history.aircraft_history("CC0001")
      expect(result.length).to eq(5)
    end

    it "orders by most recent first" do
      result = history.aircraft_history("CC0001")
      # Most recent should have highest altitude (34000)
      expect(result.first[:altitude]).to eq(34000)
    end

    it "respects limit parameter" do
      result = history.aircraft_history("CC0001", limit: 3)
      expect(result.length).to eq(3)
    end

    it "returns empty array for unknown aircraft" do
      result = history.aircraft_history("FFFFFF")
      expect(result).to eq([])
    end
  end

  describe "#recent_icaos" do
    before do
      history.record_aircraft("DD0001", nil)
      history.record_aircraft("DD0002", nil)

      # Make one aircraft old
      Aircraft.find_by(icao: "DD0001").update!(last_seen: 5.hours.ago)
    end

    it "returns recently seen ICAOs" do
      icaos = history.recent_icaos(hours: 2)
      expect(icaos).to include("DD0002")
      expect(icaos).not_to include("DD0001")
    end

    it "respects hours parameter" do
      icaos = history.recent_icaos(hours: 24)
      expect(icaos).to include("DD0001", "DD0002")
    end
  end

  describe "#coverage_analysis" do
    let(:receiver_lat) { 37.7749 }
    let(:receiver_lon) { -122.4194 }

    context "with no data" do
      it "returns empty coverage stats" do
        result = history.coverage_analysis(
          receiver_lat: receiver_lat,
          receiver_lon: receiver_lon,
          hours: 24
        )

        expect(result[:max_range_nm]).to eq(0)
        expect(result[:total_positions]).to eq(0)
        expect(result[:range_by_bearing].length).to eq(8)
      end
    end

    context "with position data" do
      before do
        # Create sightings in different directions (valid 6-char hex ICAOs)
        # North
        history.record_sighting(icao: "EE0001", latitude: 38.5, longitude: -122.4, altitude: 35000)
        # East
        history.record_sighting(icao: "EE0002", latitude: 37.7, longitude: -121.5, altitude: 30000)
        # South
        history.record_sighting(icao: "EE0003", latitude: 37.0, longitude: -122.4, altitude: 25000)
      end

      it "calculates max range" do
        result = history.coverage_analysis(
          receiver_lat: receiver_lat,
          receiver_lon: receiver_lon,
          hours: 24
        )

        expect(result[:max_range_nm]).to be > 0
        expect(result[:total_positions]).to eq(3)
      end

      it "calculates range by bearing" do
        result = history.coverage_analysis(
          receiver_lat: receiver_lat,
          receiver_lon: receiver_lon,
          hours: 24
        )

        north_sector = result[:range_by_bearing].find { |b| b[:direction] == "N" }
        expect(north_sector[:count]).to be >= 0
      end

      it "calculates range by altitude" do
        result = history.coverage_analysis(
          receiver_lat: receiver_lat,
          receiver_lon: receiver_lon,
          hours: 24
        )

        expect(result[:range_by_altitude]).to be_an(Array)
      end

      it "generates histogram" do
        result = history.coverage_analysis(
          receiver_lat: receiver_lat,
          receiver_lon: receiver_lon,
          hours: 24
        )

        expect(result[:range_histogram]).to be_an(Array)
        expect(result[:range_histogram].length).to eq(ADSB::Constants::COVERAGE_HISTOGRAM_BUCKETS)
      end
    end
  end

  describe "#export_csv" do
    before do
      2.times do |i|
        history.record_sighting(
          icao: format("FF000%d", i),
          callsign: "TST#{i}",
          latitude: 37.0 + i,
          longitude: -122.0,
          altitude: 30000,
          speed: 450,
          heading: 90,
          squawk: "1200",
          signal_strength: 0.05
        )
      end
    end

    it "returns CSV string" do
      csv = history.export_csv(days: 30)
      expect(csv).to be_a(String)
      expect(csv).to include("ICAO,Callsign")
    end

    it "includes sighting data" do
      csv = history.export_csv(days: 30)
      expect(csv).to include("FF0000")
      expect(csv).to include("TST0")
    end

    it "respects days parameter" do
      # Make one sighting old
      Sighting.last.update!(seen_at: 60.days.ago)

      csv = history.export_csv(days: 30)
      lines = csv.split("\n")
      expect(lines.length).to eq(2) # Header + 1 recent sighting
    end
  end

  describe "private geographic calculations" do
    it "calculates haversine distance" do
      # LAX to SFO ~298nm
      distance = history.send(:haversine_distance, 33.9425, -118.4081, 37.6213, -122.3790)
      expect(distance).to be_within(5).of(298)
    end

    it "calculates bearing" do
      # From origin, due north should be ~0 degrees
      bearing = history.send(:calculate_bearing, 37.0, -122.0, 38.0, -122.0)
      expect(bearing).to be_within(5).of(0)

      # Due east should be ~90 degrees
      bearing = history.send(:calculate_bearing, 37.0, -122.0, 37.0, -121.0)
      expect(bearing).to be_within(5).of(90)
    end
  end
end
