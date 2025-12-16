class Api::CoverageController < ApplicationController
  include ADSB::Constants

  def show
    lat = params[:lat]&.to_f
    lon = params[:lon]&.to_f
    hours = (params[:hours] || DEFAULT_COVERAGE_HOURS).to_i

    unless lat && lon && lat != 0 && lon != 0
      return render json: { error: "Receiver lat/lon required" }
    end

    if AdsbService.receiver&.history
      render json: AdsbService.receiver.history.coverage_analysis(receiver_lat: lat, receiver_lon: lon, hours: hours)
    else
      render json: { error: "History not available" }
    end
  end
end
