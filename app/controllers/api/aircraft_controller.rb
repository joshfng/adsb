class Api::AircraftController < ApplicationController
  def index
    render json: { aircraft: AdsbService.receiver&.aircraft_list || [] }
  end

  def show
    icao = params[:icao].upcase

    # Get live data from receiver
    live_data = AdsbService.receiver&.aircraft_list&.find { |a| a[:icao] == icao }

    # Get FAA registration data
    faa_data = AdsbService.faa_lookup&.lookup(icao)

    if live_data || faa_data
      render json: {
        icao: icao,
        live: live_data,
        registration: faa_data
      }
    else
      render json: { error: "Aircraft not found" }, status: :not_found
    end
  end
end
