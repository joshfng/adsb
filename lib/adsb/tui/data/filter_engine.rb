# frozen_string_literal: true

require_relative "../../constants"

module ADSB
  module TUI
    module Data
      # Filtering and sorting logic for aircraft list
      class FilterEngine
        include ADSB::Constants

        # Military callsign patterns (ported from web GUI)
        MILITARY_PATTERNS = [
          /^REACH\d/i, /^RCH\d/i, /^EVAC\d/i, /^DUKE\d/i, /^KING\d/i,
          /^PEDRO\d/i, /^JOLLY\d/i, /^RESCUE/i, /^PACK\d/i, /^SWIFT\d/i,
          /^TEAL\d/i, /^BLADE\d/i, /^DEMON\d/i, /^CHAOS\d/i, /^HAVOC\d/i,
          /^TOPCAT/i, /^SENTRY/i, /^AWACS/i, /^DRAGN/i, /^VIPER\d/i,
          /^COBRA\d/i, /^PYTHON/i, /^RAPTOR/i, /^EAGLE\d/i, /^HAWK\d/i,
          /^TALON\d/i, /^HUNTER/i, /^REAPER/i, /^STING\d/i
        ].freeze

        # Military ICAO prefixes (US military ranges)
        MILITARY_ICAO_PREFIXES = %w[AE AF].freeze

        # Law enforcement callsign patterns
        LAW_ENFORCEMENT_PATTERNS = [
          /^POLICE/i, /^N\d*HP$/i, /^N\d*PD$/i, /^N\d*SP$/i,
          /^N\d*CP$/i, /^N\d*LP$/i, /SHERIFF/i, /TROOPER/i,
          /^COPTER\d/i, /^PATROL/i
        ].freeze

        # Known law enforcement ICAOs (Ohio area)
        LAW_ENFORCEMENT_ICAOS = Set.new(%w[
          A03815 A05216 A08F0B A0D7D1 A11A63 A15B98 A1C7B0 A21DC6
          A22A87 A23000 A27D63 A2A7F0 A30000 A37D21 A3B5B3 A48000
          A4B8D4 A50000 A52B74 A54A68 A5F58E A64000 A66A8C
        ]).freeze

        SORT_KEYS = {
          icao: ->(a) { a[:icao] || "" },
          callsign: ->(a) { a[:callsign] || "ZZZZ" },
          altitude: ->(a) { -(a[:altitude] || -99_999) },
          distance: ->(a) { a[:distance] || TUI_DEFAULT_SORT_DISTANCE },
          speed: ->(a) { -(a[:speed] || 0) },
          signal: ->(a) { -(a[:signal_strength] || 0) },
          age: ->(a) { a[:last_seen] ? Time.now - a[:last_seen] : 9999 },
          heading: ->(a) { a[:heading] || 999 },
          vrate: ->(a) { -(a[:vertical_rate]&.abs || 0) },
          squawk: ->(a) { a[:squawk] || "ZZZZ" }
        }.freeze

        attr_accessor :search_text, :sort_key, :sort_ascending
        attr_accessor :min_altitude, :max_altitude
        attr_accessor :position_only, :military_only, :police_only

        def initialize
          @search_text = ""
          @sort_key = :distance
          @sort_ascending = true
          @min_altitude = 0
          @max_altitude = 100_000
          @position_only = false
          @military_only = false
          @police_only = false
        end

        def apply(aircraft_list)
          result = aircraft_list.dup
          result = filter_search(result)
          result = filter_altitude(result)
          result = filter_position(result)
          result = filter_military(result)
          result = filter_police(result)
          sort(result)
        end

        # Returns array of active filter descriptions
        def active_filters
          filters = []
          filters << "\"#{@search_text}\"" unless @search_text.empty?
          filters << "Alt:#{@min_altitude}-#{@max_altitude}" if altitude_filtered?
          filters << "Pos" if @position_only
          filters << "Mil" if @military_only
          filters << "LEO" if @police_only
          filters.join(" ")
        end

        def any_active?
          !@search_text.empty? || altitude_filtered? || @position_only || @military_only || @police_only
        end

        # Check if aircraft is military
        def military?(aircraft)
          icao = aircraft[:icao].to_s.upcase
          callsign = aircraft[:callsign].to_s

          # Check ICAO prefix
          return true if MILITARY_ICAO_PREFIXES.any? { |prefix| icao.start_with?(prefix) }

          # Check callsign patterns
          return true if MILITARY_PATTERNS.any? { |pattern| callsign.match?(pattern) }

          # Behavioral detection: high altitude + high speed
          alt = aircraft[:altitude].to_i
          spd = aircraft[:speed].to_i
          return true if alt > 25_000 && spd > 350

          false
        end

        # Check if aircraft is law enforcement
        def police?(aircraft)
          icao = aircraft[:icao].to_s.upcase
          callsign = aircraft[:callsign].to_s

          # Check known ICAOs
          return true if LAW_ENFORCEMENT_ICAOS.include?(icao)

          # Check callsign patterns
          LAW_ENFORCEMENT_PATTERNS.any? { |pattern| callsign.match?(pattern) }
        end

        private

        def filter_search(list)
          return list if @search_text.empty?

          pattern = Regexp.new(Regexp.escape(@search_text), Regexp::IGNORECASE)
          list.select do |ac|
            (ac[:icao] || "").match?(pattern) ||
              (ac[:callsign] || "").match?(pattern)
          end
        end

        def filter_altitude(list)
          return list unless altitude_filtered?

          list.select do |ac|
            alt = ac[:altitude]
            next true unless alt # Keep aircraft without altitude data

            alt >= @min_altitude && alt <= @max_altitude
          end
        end

        def filter_position(list)
          return list unless @position_only

          list.select { |ac| ac[:latitude] && ac[:longitude] }
        end

        def filter_military(list)
          return list unless @military_only

          list.select { |ac| military?(ac) }
        end

        def filter_police(list)
          return list unless @police_only

          list.select { |ac| police?(ac) }
        end

        def sort(list)
          sorter = SORT_KEYS[@sort_key] || SORT_KEYS[:distance]
          sorted = list.sort_by(&sorter)
          @sort_ascending ? sorted : sorted.reverse
        end

        def altitude_filtered?
          @min_altitude > 0 || @max_altitude < 100_000
        end
      end
    end
  end
end
