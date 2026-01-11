require 'rails_helper'

RSpec.describe "Api::Feeds", type: :request do
  let(:mock_receiver) { instance_double("SDRReceiver") }
  let(:aircraft_list) do
    [
      {
        icao: "A12345",
        callsign: "UAL123",
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 35000,
        heading: 90,
        speed: 450,
        vertical_rate: 0,
        squawk: "1200",
        last_seen: Time.current,
        messages: 100
      }
    ]
  end

  describe "GET /beast" do
    it "returns http success" do
      get "/api/feed/beast"
      expect(response).to have_http_status(:success)
    end

    it "returns aircraft in beast format" do
      allow(AdsbService).to receive(:receiver).and_return(mock_receiver)
      allow(mock_receiver).to receive(:aircraft_list).and_return(aircraft_list)

      get "/api/feed/beast"

      json = JSON.parse(response.body)
      expect(json["aircraft"]).to be_an(Array)
      expect(json["aircraft"].first["hex"]).to eq("A12345")
      expect(json["aircraft"].first["flight"]).to eq("UAL123")
    end
  end

  describe "GET /sbs" do
    it "returns http success" do
      get "/api/feed/sbs"
      expect(response).to have_http_status(:success)
    end

    it "returns SBS format lines" do
      allow(AdsbService).to receive(:receiver).and_return(mock_receiver)
      allow(mock_receiver).to receive(:aircraft_list).and_return(aircraft_list)

      get "/api/feed/sbs"

      expect(response.body).to include("MSG,3")
      expect(response.body).to include("A12345")
    end

    it "filters aircraft without position" do
      no_position = [ { icao: "B67890", latitude: nil, longitude: nil } ]
      allow(AdsbService).to receive(:receiver).and_return(mock_receiver)
      allow(mock_receiver).to receive(:aircraft_list).and_return(no_position)

      get "/api/feed/sbs"

      expect(response.body).to be_empty
    end
  end

  describe "GET /status" do
    it "returns http success" do
      get "/api/feed/status"
      expect(response).to have_http_status(:success)
    end

    it "includes feed endpoints" do
      get "/api/feed/status"

      json = JSON.parse(response.body)
      expect(json["feeds"]["beast_endpoint"]).to eq("/api/feed/beast")
      expect(json["feeds"]["sbs_endpoint"]).to eq("/api/feed/sbs")
    end

    it "includes stats when receiver is running" do
      allow(AdsbService).to receive(:receiver).and_return(mock_receiver)
      allow(mock_receiver).to receive(:running).and_return(true)
      allow(mock_receiver).to receive(:aircraft_list).and_return(aircraft_list)
      allow(mock_receiver).to receive(:get_stats).and_return({
        uptime_seconds: 3600,
        messages_total: 10000
      })

      get "/api/feed/status"

      json = JSON.parse(response.body)
      expect(json["local"]["running"]).to be(true)
      expect(json["local"]["uptime_seconds"]).to eq(3600)
    end
  end
end
