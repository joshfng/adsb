# frozen_string_literal: true

class Api::OpenskyController < ApplicationController
  include ADSB::Constants

  CACHE_KEY_PREFIX = "opensky_flight_"

  def show
    icao = params[:icao].to_s.upcase.strip

    # Validate ICAO format (6-character hex)
    unless icao.match?(/\A[0-9A-F]{6}\z/)
      return render json: { flight: nil, error: "Invalid ICAO format" }, status: :bad_request
    end

    # Check cache first (thread-safe via Rails.cache)
    cache_key = "#{CACHE_KEY_PREFIX}#{icao}"
    cached = Rails.cache.read(cache_key)
    return render json: { flight: cached } if cached

    begin
      flight_data = fetch_from_opensky(icao)

      if flight_data
        # Cache with TTL (thread-safe)
        Rails.cache.write(cache_key, flight_data, expires_in: OPENSKY_CACHE_SEC.seconds)
        render json: { flight: flight_data }
      else
        render json: { flight: nil }
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      ADSB.logger.warn "OpenSky API timeout: #{e.message}"
      render json: { flight: nil, error: "API timeout" }, status: :gateway_timeout
    rescue JSON::ParserError => e
      ADSB.logger.warn "OpenSky API invalid response: #{e.message}"
      render json: { flight: nil, error: "Invalid API response" }, status: :bad_gateway
    rescue OpenSSL::SSL::SSLError => e
      ADSB.logger.error "OpenSky SSL error: #{e.message}"
      render json: { flight: nil, error: "SSL error" }, status: :bad_gateway
    rescue SocketError, Errno::ECONNREFUSED => e
      ADSB.logger.warn "OpenSky API connection error: #{e.message}"
      render json: { flight: nil, error: "Connection error" }, status: :service_unavailable
    end
  end

  private

  def fetch_from_opensky(icao)
    uri = URI("https://opensky-network.org/api/flights/aircraft")
    uri.query = URI.encode_www_form(
      icao24: icao.downcase,
      begin: Time.current.to_i - OPENSKY_LOOKBACK_SEC,
      end: Time.current.to_i
    )

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout = HTTP_TIMEOUT_SEC
    http.read_timeout = HTTP_TIMEOUT_SEC

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    return nil unless response.is_a?(Net::HTTPSuccess)

    flights = JSON.parse(response.body)
    return nil unless flights.is_a?(Array) && !flights.empty?

    # Get the most recent flight
    latest = flights.max_by { |f| f["lastSeen"] || 0 }
    {
      callsign: latest["callsign"]&.strip,
      origin: latest["estDepartureAirport"],
      destination: latest["estArrivalAirport"],
      first_seen: latest["firstSeen"],
      last_seen: latest["lastSeen"]
    }
  end
end
