class Api::StatusController < ApplicationController
  def show
    render json: {
      running: AdsbService.receiver&.running || false,
      aircraft_count: AdsbService.receiver&.aircraft_list&.length || 0
    }
  end

  def stats
    if AdsbService.receiver&.running
      render json: AdsbService.receiver.get_stats
    else
      render json: { error: "Receiver not running" }
    end
  end
end
