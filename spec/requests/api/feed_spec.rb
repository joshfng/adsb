require 'rails_helper'

RSpec.describe "Api::Feeds", type: :request do
  describe "GET /beast" do
    it "returns http success" do
      get "/api/feed/beast"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /sbs" do
    it "returns http success" do
      get "/api/feed/sbs"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /status" do
    it "returns http success" do
      get "/api/feed/status"
      expect(response).to have_http_status(:success)
    end
  end

end
