require 'rails_helper'

RSpec.describe "Api::Coverages", type: :request do
  describe "GET /api/coverage" do
    it "returns http success" do
      get "/api/coverage"
      expect(response).to have_http_status(:success)
    end
  end
end
