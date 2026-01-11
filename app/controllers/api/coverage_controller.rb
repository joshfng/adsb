# frozen_string_literal: true

class Api::CoverageController < ApplicationController
  include ADSB::Constants

  before_action :require_history

  def show
    lat = params[:lat]&.to_f
    lon = params[:lon]&.to_f
    hours = (params[:hours] || DEFAULT_COVERAGE_HOURS).to_i

    unless lat && lon && lat != 0 && lon != 0
      return render json: { error: "Receiver lat/lon required" }
    end

    render json: AdsbService.receiver.history.coverage_analysis(receiver_lat: lat, receiver_lon: lon, hours: hours)
  end
end
