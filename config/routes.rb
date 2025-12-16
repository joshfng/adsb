Rails.application.routes.draw do
  # Root
  root "home#index"

  # API routes
  namespace :api do
    # Status
    get "status", to: "status#show"
    get "stats", to: "status#stats"

    # Aircraft
    get "aircraft", to: "aircraft#index"
    get "aircraft/:icao", to: "aircraft#show"

    # History
    get "history/stats", to: "history#stats"
    get "history/heatmap", to: "history#heatmap"
    get "history/aircraft/:icao", to: "history#aircraft"

    # Export
    get "export/csv", to: "export#csv"

    # Feed
    get "feed/beast", to: "feed#beast"
    get "feed/sbs", to: "feed#sbs"
    get "feed/status", to: "feed#status"

    # Coverage
    get "coverage", to: "coverage#show"

    # OpenSky
    get "opensky/:icao", to: "opensky#show"
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
