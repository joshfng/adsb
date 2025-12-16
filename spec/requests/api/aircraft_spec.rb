require 'rails_helper'

RSpec.describe "Api::Aircrafts", type: :request do
  describe "GET /api/aircraft" do
    it "returns http success" do
      get "/api/aircraft"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /api/aircraft/:icao" do
    it "returns valid response" do
      get "/api/aircraft/ABC123"
      # 404 is expected if aircraft not currently tracked
      expect(response).to have_http_status(:success).or have_http_status(:not_found)
    end
  end
end
