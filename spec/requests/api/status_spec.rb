require 'rails_helper'

RSpec.describe "Api::Statuses", type: :request do
  describe "GET /api/status" do
    it "returns http success" do
      get "/api/status"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /api/stats" do
    it "returns http success" do
      get "/api/stats"
      expect(response).to have_http_status(:success)
    end
  end
end
