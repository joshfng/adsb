require 'rails_helper'

RSpec.describe "Api::Histories", type: :request do
  describe "GET /api/history/stats" do
    it "returns valid response" do
      get "/api/history/stats"
      # 503 is expected if receiver/history not available
      expect(response).to have_http_status(:success).or have_http_status(:service_unavailable)
    end
  end

  describe "GET /api/history/heatmap" do
    it "returns valid response" do
      get "/api/history/heatmap"
      # 503 is expected if receiver/history not available
      expect(response).to have_http_status(:success).or have_http_status(:service_unavailable)
    end
  end

  describe "GET /api/history/aircraft/:icao" do
    it "returns valid response" do
      get "/api/history/aircraft/ABC123"
      # 503 is expected if history service not available
      expect(response).to have_http_status(:success).or have_http_status(:service_unavailable)
    end
  end
end
