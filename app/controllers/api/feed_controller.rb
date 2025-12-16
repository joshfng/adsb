class Api::FeedController < ApplicationController
  def beast
    aircraft_list = AdsbService.receiver&.aircraft_list || []

    render json: {
      aircraft: aircraft_list.map { |ac|
        {
          hex: ac[:icao],
          flight: ac[:callsign],
          lat: ac[:latitude],
          lon: ac[:longitude],
          altitude: ac[:altitude],
          track: ac[:heading],
          speed: ac[:speed],
          vert_rate: ac[:vertical_rate],
          squawk: ac[:squawk],
          seen: ac[:last_seen]&.to_i,
          messages: ac[:messages]
        }
      }
    }
  end

  def sbs
    aircraft_list = AdsbService.receiver&.aircraft_list || []

    lines = aircraft_list.filter_map do |ac|
      next unless ac[:latitude] && ac[:longitude]

      now = Time.current
      date = now.strftime("%Y/%m/%d")
      time = now.strftime("%H:%M:%S.000")

      # MSG,3 = ES Airborne Position Message
      "MSG,3,1,1,#{ac[:icao]},1,#{date},#{time},#{date},#{time},#{ac[:callsign]},#{ac[:altitude]},#{ac[:speed]},#{ac[:heading]},#{ac[:latitude]},#{ac[:longitude]},#{ac[:vertical_rate]},,,,0"
    end

    render plain: lines.join("\n")
  end

  def status
    status_data = {
      local: {
        running: AdsbService.receiver&.running || false,
        aircraft_count: AdsbService.receiver&.aircraft_list&.length || 0
      },
      feeds: {
        beast_endpoint: "/api/feed/beast",
        sbs_endpoint: "/api/feed/sbs"
      }
    }

    # Add message rates if available
    if AdsbService.receiver&.running
      stats = AdsbService.receiver.get_stats
      status_data[:local][:uptime_seconds] = stats[:uptime_seconds] if stats[:uptime_seconds]
      status_data[:local][:messages_per_second] = stats[:messages_per_second] if stats[:messages_per_second]
      status_data[:local][:messages_total] = stats[:messages_total] if stats[:messages_total]
    end

    render json: status_data
  end
end
