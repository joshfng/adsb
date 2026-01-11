require 'rails_helper'

RSpec.describe "Api::Histories", type: :request do
  let(:mock_receiver) { instance_double("SDRReceiver") }
  let(:mock_history) { instance_double("FlightHistory") }

  before do
    allow(AdsbService).to receive(:receiver).and_return(mock_receiver)
    allow(mock_receiver).to receive(:history).and_return(mock_history)
  end

  describe "GET /api/history/stats" do
    it "returns stats when history available" do
      allow(mock_history).to receive(:get_stats).and_return({
        total_aircraft_seen: 100,
        sightings_today: 500
      })

      get "/api/history/stats"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["total_aircraft_seen"]).to eq(100)
    end

    it "returns 503 when history not available" do
      allow(AdsbService).to receive(:receiver).and_return(nil)

      get "/api/history/stats"

      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe "GET /api/history/heatmap" do
    it "returns positions" do
      allow(mock_history).to receive(:get_positions).and_return([
        { lat: 37.77, lon: -122.42, count: 10 }
      ])

      get "/api/history/heatmap"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["positions"]).to be_an(Array)
    end

    it "accepts hours parameter" do
      allow(mock_history).to receive(:get_positions).with(hours: 48, limit: 5000).and_return([])

      get "/api/history/heatmap", params: { hours: 48 }

      expect(response).to have_http_status(:success)
    end

    it "rejects invalid hours parameter" do
      get "/api/history/heatmap", params: { hours: "abc" }

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects invalid limit parameter" do
      get "/api/history/heatmap", params: { limit: "xyz" }

      expect(response).to have_http_status(:bad_request)
    end

    it "clamps hours to max 168" do
      allow(mock_history).to receive(:get_positions).with(hours: 168, limit: 5000).and_return([])

      get "/api/history/heatmap", params: { hours: 500 }

      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /api/history/aircraft/:icao" do
    it "returns aircraft history" do
      allow(mock_history).to receive(:aircraft_history).with("ABC123", limit: 5000).and_return([
        { altitude: 35000, seen_at: "2024-01-01T12:00:00Z" }
      ])

      get "/api/history/aircraft/ABC123"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["history"]).to be_an(Array)
    end

    it "normalizes lowercase ICAO" do
      allow(mock_history).to receive(:aircraft_history).with("ABC123", limit: 5000).and_return([])

      get "/api/history/aircraft/abc123"

      expect(response).to have_http_status(:success)
    end

    it "rejects invalid ICAO format" do
      get "/api/history/aircraft/INVALID"

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects short ICAO" do
      get "/api/history/aircraft/ABC"

      expect(response).to have_http_status(:bad_request)
    end
  end
end
