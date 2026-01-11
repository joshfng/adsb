require 'rails_helper'

RSpec.describe "Api::Coverages", type: :request do
  describe "GET /api/coverage" do
    it "returns valid response" do
      get "/api/coverage"
      # 503 is expected if receiver/history not available
      expect(response).to have_http_status(:success).or have_http_status(:service_unavailable)
    end
  end
end
