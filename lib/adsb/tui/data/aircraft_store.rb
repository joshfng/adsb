# frozen_string_literal: true

require_relative '../../constants'

module ADSB
  module TUI
    module Data
      # Thread-safe storage for aircraft data
      class AircraftStore
        include ADSB::Constants

        def initialize
          @aircraft = {}
          @mutex = Mutex.new
          @changed = false
        end

        # Update aircraft data (called from receiver callback thread)
        def update(aircraft_data)
          @mutex.synchronize do
            icao = aircraft_data[:icao]
            return unless icao

            @aircraft[icao] = aircraft_data.dup
            @changed = true
          end
        end

        # Bulk update from aircraft list
        def update_all(aircraft_list)
          @mutex.synchronize do
            @aircraft.clear
            aircraft_list.each do |ac|
              @aircraft[ac[:icao]] = ac.dup if ac[:icao]
            end
            @changed = true
          end
        end

        # Get all aircraft (returns copy)
        def all
          @mutex.synchronize { @aircraft.values.map(&:dup) }
        end

        # Find single aircraft by ICAO
        def find(icao)
          @mutex.synchronize { @aircraft[icao]&.dup }
        end

        # Check if data changed since last check (resets flag)
        def changed?
          @mutex.synchronize do
            result = @changed
            @changed = false
            result
          end
        end

        # Remove stale aircraft
        def prune_stale(timeout_sec = AIRCRAFT_TIMEOUT_SEC)
          @mutex.synchronize do
            now = Time.now
            @aircraft.delete_if do |_, data|
              last_seen = data[:last_seen]
              last_seen.nil? || (now - last_seen) > timeout_sec
            end
          end
        end

        # Aircraft count
        def count
          @mutex.synchronize { @aircraft.size }
        end
      end
    end
  end
end
