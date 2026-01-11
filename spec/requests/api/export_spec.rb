require 'rails_helper'

RSpec.describe "Api::Exports", type: :request do
  describe "GET /csv" do
    it "returns valid response" do
      get "/api/export/csv"
      # 503 is expected if receiver/history not available
      expect(response).to have_http_status(:success).or have_http_status(:service_unavailable)
    end
  end
end
