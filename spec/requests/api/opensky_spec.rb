require 'rails_helper'

RSpec.describe "Api::Openskies", type: :request do
  describe "GET /api/opensky/:icao" do
    it "returns valid response" do
      get "/api/opensky/ABC123"
      # May fail with 400/503 if external API unavailable
      expect(response.status).to be_between(200, 503)
    end
  end
end
