# frozen_string_literal: true

require_relative "constants"

# Flight History Database (ActiveRecord version)
# Records all aircraft sightings for statistics and history
class FlightHistory
  include ADSB::Constants

  def initialize
    # No mutex needed - ActiveRecord handles thread safety
  end

  # Record an aircraft sighting
  def record_sighting(aircraft)
    return unless aircraft[:icao]

    Sighting.create!(
      icao: aircraft[:icao],
      callsign: aircraft[:callsign],
      latitude: aircraft[:latitude],
      longitude: aircraft[:longitude],
      altitude: aircraft[:altitude],
      speed: aircraft[:speed],
      heading: aircraft[:heading],
      squawk: aircraft[:squawk],
      signal_strength: aircraft[:signal_strength]
    )
  end

  # Record a unique aircraft (first time seen today)
  # Uses upsert to handle race conditions atomically
  def record_aircraft(icao, callsign = nil)
    now = Time.current

    # Try to find and update existing aircraft atomically
    # Uses UPDATE with RETURNING to avoid race conditions
    result = Aircraft.where(icao: icao).update_all(
      [
        "last_seen = ?, callsign = COALESCE(?, callsign), sighting_count = sighting_count + 1",
        now,
        callsign
      ]
    )

    # If no rows updated, create new aircraft (handles race via unique constraint)
    if result == 0
      Aircraft.create!(
        icao: icao,
        callsign: callsign,
        first_seen: now,
        last_seen: now,
        sighting_count: 1
      )
    end
  rescue ActiveRecord::RecordNotUnique
    # Another thread created it, retry the update
    retry
  end

  # Get statistics
  def get_stats
    {
      total_aircraft_seen: total_aircraft_count,
      aircraft_today: aircraft_count_today,
      sightings_today: sightings_count_today,
      sightings_total: total_sightings_count,
      busiest_hours: busiest_hours,
      most_seen_aircraft: most_seen_aircraft(10),
      hourly_activity: hourly_activity_today,
      daily_activity: daily_activity(7)
    }
  end

  # Get position history for heatmap
  def get_positions(hours: 24, limit: 10000)
    Sighting.where("latitude IS NOT NULL AND longitude IS NOT NULL")
            .where("seen_at > ?", hours.hours.ago)
            .select("ROUND(latitude, 2) as lat, ROUND(longitude, 2) as lon, COUNT(*) as count")
            .group("lat, lon")
            .order("count DESC")
            .limit(limit)
            .map { |row| { lat: row.lat, lon: row.lon, count: row.count } }
  end

  # Get recent flight history for an aircraft
  def aircraft_history(icao, limit: 100)
    Sighting.where(icao: icao)
            .order(seen_at: :desc)
            .limit(limit)
            .map do |s|
              {
                callsign: s.callsign,
                latitude: s.latitude,
                longitude: s.longitude,
                altitude: s.altitude,
                speed: s.speed,
                heading: s.heading,
                seen_at: s.seen_at&.iso8601
              }
            end
  end

  # Get recently seen ICAOs for ICAO recovery from short messages
  # Returns array of ICAO hex strings seen in the last N hours
  def recent_icaos(hours: 2)
    Aircraft.where("last_seen > ?", hours.hours.ago).pluck(:icao)
  end

  # Coverage analysis - calculate range statistics from receiver position
  def coverage_analysis(receiver_lat:, receiver_lon:, hours: DEFAULT_COVERAGE_HOURS)
    positions = Sighting.where("latitude IS NOT NULL AND longitude IS NOT NULL")
                        .where("seen_at > ?", hours.hours.ago)
                        .pluck(:latitude, :longitude, :altitude, :signal_strength)

    return empty_coverage_stats if positions.empty?

    # Calculate distance and bearing for each position
    range_data = positions.map do |lat, lon, alt, signal|
      distance = haversine_distance(receiver_lat, receiver_lon, lat, lon)
      bearing = calculate_bearing(receiver_lat, receiver_lon, lat, lon)
      { distance: distance, bearing: bearing, altitude: alt || 0, signal: signal || 0 }
    end

    # Overall stats
    distances = range_data.map { |d| d[:distance] }
    max_range = distances.max
    avg_range = distances.sum / distances.size
    range_records = range_data.sort_by { |d| -d[:distance] }.first(10)

    # Range by bearing (8 directions)
    range_by_bearing = COVERAGE_DIRECTIONS.each_with_index.map do |dir, i|
      half_sector = COVERAGE_DEGREES_PER_SECTOR / 2.0
      start_angle = (i * COVERAGE_DEGREES_PER_SECTOR - half_sector) % 360
      end_angle = (i * COVERAGE_DEGREES_PER_SECTOR + half_sector) % 360

      in_sector = range_data.select do |d|
        if start_angle > end_angle  # Wraps around 0 (North)
          d[:bearing] >= start_angle || d[:bearing] < end_angle
        else
          d[:bearing] >= start_angle && d[:bearing] < end_angle
        end
      end

      max_in_sector = in_sector.map { |d| d[:distance] }.max || 0
      count = in_sector.size
      { direction: dir, max_range: max_in_sector.round(1), count: count }
    end

    # Range by altitude bands (in feet)
    range_by_altitude = ALTITUDE_BANDS.map do |band|
      in_band = range_data.select { |d| d[:altitude] >= band[:min] && d[:altitude] < band[:max] }
      max_in_band = in_band.map { |d| d[:distance] }.max || 0
      avg_in_band = in_band.empty? ? 0 : in_band.map { |d| d[:distance] }.sum / in_band.size
      { band: band[:name], max_range: max_in_band.round(1), avg_range: avg_in_band.round(1), count: in_band.size }
    end

    # Range histogram
    histogram = Array.new(COVERAGE_HISTOGRAM_BUCKETS, 0)
    distances.each do |d|
      bucket = [ (d / COVERAGE_HISTOGRAM_BUCKET_NM).to_i, COVERAGE_HISTOGRAM_BUCKETS - 1 ].min
      histogram[bucket] += 1
    end

    {
      max_range_nm: max_range.round(1),
      avg_range_nm: avg_range.round(1),
      total_positions: positions.size,
      range_by_bearing: range_by_bearing,
      range_by_altitude: range_by_altitude,
      range_histogram: histogram,
      range_records: range_records.map { |r|
        { distance_nm: r[:distance].round(1), bearing: r[:bearing].round, altitude: r[:altitude] }
      }
    }
  end

  # Export all sightings to CSV format
  def export_csv(days: 30)
    csv = "ICAO,Callsign,Latitude,Longitude,Altitude,Speed,Heading,Squawk,Signal,Timestamp\n"

    Sighting.where("seen_at > ?", days.days.ago)
            .order(seen_at: :desc)
            .each do |s|
      csv += [
        s.icao, s.callsign, s.latitude, s.longitude, s.altitude,
        s.speed, s.heading, s.squawk, s.signal_strength, s.seen_at&.iso8601
      ].join(",") + "\n"
    end
    csv
  end

  private

  def total_aircraft_count
    Aircraft.count
  end

  def aircraft_count_today
    Sighting.where("seen_at > ?", Time.current.beginning_of_day).distinct.count(:icao)
  end

  def sightings_count_today
    Sighting.where("seen_at > ?", Time.current.beginning_of_day).count
  end

  def total_sightings_count
    Sighting.count
  end

  def busiest_hours
    Sighting.where("seen_at > ?", 7.days.ago)
            .group("strftime('%H', seen_at)")
            .order("count_all DESC")
            .limit(5)
            .count
            .map { |hour, count| { hour: hour, count: count } }
  end

  def most_seen_aircraft(limit)
    Aircraft.order(sighting_count: :desc)
            .limit(limit)
            .map { |a| { icao: a.icao, callsign: a.callsign, count: a.sighting_count, last_seen: a.last_seen&.iso8601 } }
  end

  def hourly_activity_today
    Sighting.where("seen_at > ?", Time.current.beginning_of_day)
            .group(Arel.sql("strftime('%H', seen_at)"))
            .order(Arel.sql("strftime('%H', seen_at)"))
            .count
            .map { |hour, count| { hour: hour.to_i, count: count } }
  end

  def daily_activity(days)
    Sighting.where("seen_at > ?", days.days.ago)
            .group(Arel.sql("date(seen_at)"))
            .order(Arel.sql("date(seen_at)"))
            .distinct
            .count(:icao)
            .map { |date, count| { date: date, count: count } }
  end

  # Haversine distance in nautical miles
  def haversine_distance(lat1, lon1, lat2, lon2)
    lat1_rad = lat1 * DEGREES_TO_RADIANS
    lat2_rad = lat2 * DEGREES_TO_RADIANS
    delta_lat = (lat2 - lat1) * DEGREES_TO_RADIANS
    delta_lon = (lon2 - lon1) * DEGREES_TO_RADIANS

    a = Math.sin(delta_lat / 2)**2 +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(delta_lon / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    EARTH_RADIUS_NM * c
  end

  # Calculate bearing from point 1 to point 2 (0-360 degrees, 0 = North)
  def calculate_bearing(lat1, lon1, lat2, lon2)
    lat1_rad = lat1 * DEGREES_TO_RADIANS
    lat2_rad = lat2 * DEGREES_TO_RADIANS
    delta_lon = (lon2 - lon1) * DEGREES_TO_RADIANS

    x = Math.sin(delta_lon) * Math.cos(lat2_rad)
    y = Math.cos(lat1_rad) * Math.sin(lat2_rad) -
        Math.sin(lat1_rad) * Math.cos(lat2_rad) * Math.cos(delta_lon)

    bearing = Math.atan2(x, y) / DEGREES_TO_RADIANS
    (bearing + 360) % 360
  end

  def empty_coverage_stats
    {
      max_range_nm: 0,
      avg_range_nm: 0,
      total_positions: 0,
      range_by_bearing: COVERAGE_DIRECTIONS.map { |d| { direction: d, max_range: 0, count: 0 } },
      range_by_altitude: [],
      range_histogram: Array.new(COVERAGE_HISTOGRAM_BUCKETS, 0),
      range_records: []
    }
  end
end
