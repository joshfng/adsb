require 'rails_helper'

RSpec.describe "Api::Exports", type: :request do
  describe "GET /csv" do
    it "returns http success" do
      get "/api/export/csv"
      expect(response).to have_http_status(:success)
    end
  end

end
