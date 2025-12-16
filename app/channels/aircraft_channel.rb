class AircraftChannel < ApplicationCable::Channel
  def subscribed
    stream_from "aircraft"

    # Send current aircraft list when client connects
    if AdsbService.receiver
      transmit({ type: "aircraft_list", aircraft: AdsbService.receiver.aircraft_list })
    end
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  # Handle get_aircraft command from client
  def get_aircraft
    transmit({ type: "aircraft_list", aircraft: AdsbService.receiver&.aircraft_list || [] })
  end
end
