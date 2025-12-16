# frozen_string_literal: true

class Api::HistoryController < ApplicationController
  before_action :validate_hours, only: [ :heatmap ]
  before_action :validate_limit, only: [ :heatmap, :aircraft ]
  before_action :validate_icao, only: [ :aircraft ]

  def stats
    history = AdsbService.receiver&.history
    unless history
      return render json: { error: "History service not available" }, status: :service_unavailable
    end

    render json: history.get_stats
  end

  def heatmap
    history = AdsbService.receiver&.history
    unless history
      return render json: { error: "History service not available" }, status: :service_unavailable
    end

    positions = history.get_positions(hours: @hours, limit: @limit)
    render json: { positions: positions }
  end

  def aircraft
    history = AdsbService.receiver&.history
    unless history
      return render json: { error: "History service not available" }, status: :service_unavailable
    end

    history_data = history.aircraft_history(@icao, limit: @limit)
    render json: { history: history_data }
  end

  private

  def validate_hours
    hours = params[:hours].to_s
    if hours.present? && !hours.match?(/\A\d+\z/)
      return render json: { error: "Invalid hours parameter" }, status: :bad_request
    end
    @hours = hours.present? ? hours.to_i.clamp(1, 168) : 24  # Max 7 days
  end

  def validate_limit
    limit = params[:limit].to_s
    if limit.present? && !limit.match?(/\A\d+\z/)
      return render json: { error: "Invalid limit parameter" }, status: :bad_request
    end
    @limit = limit.present? ? limit.to_i.clamp(1, 10000) : 5000
  end

  def validate_icao
    icao = params[:icao].to_s.upcase.strip
    unless icao.match?(/\A[0-9A-F]{6}\z/)
      return render json: { error: "Invalid ICAO format" }, status: :bad_request
    end
    @icao = icao
  end
end
