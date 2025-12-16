# frozen_string_literal: true

require_relative 'base_window'
require_relative '../../faa_lookup'

module ADSB
  module TUI
    module Windows
      # Aircraft detail panel showing full info and FAA data
      class DetailPanel < BaseWindow
        def initialize(height:, width:, top:, left:)
          super(height: height, width: width, top: top, left: left, title: 'Detail', border: true)
          @aircraft = nil
          @faa_data = nil
          @faa_lookup = nil
        end

        def set_aircraft(aircraft)
          return if aircraft.nil? && @aircraft.nil?
          return if aircraft && @aircraft && aircraft[:icao] == @aircraft[:icao]

          @aircraft = aircraft
          @faa_data = nil

          if aircraft && aircraft[:icao]
            @faa_lookup ||= FAALookup.new
            @faa_data = @faa_lookup.lookup(aircraft[:icao])
          end
        end

        def draw
          @window.clear
          draw_border
          draw_title

          if @aircraft.nil?
            draw_no_selection
          else
            draw_aircraft_info
          end
        end

        private

        def draw_no_selection
          start_row, start_col, c_height, c_width = content_area
          msg = 'Select aircraft with Enter'
          row = start_row + c_height / 2
          col = start_col + (c_width - msg.length) / 2
          draw_text(row, col, msg, Color::Scheme::DIM)
        end

        def draw_aircraft_info
          start_row, start_col, _, c_width = content_area
          row = start_row

          # Callsign header
          callsign = @aircraft[:callsign] || @aircraft[:icao] || 'Unknown'
          draw_text(row, start_col, callsign, Color::Scheme::HEADER, Curses::A_BOLD)
          row += 1

          # Badges
          badges = []
          badges << '[MIL]' if military?
          badges << '[LEO]' if police?
          badges << '[EMER]' if emergency?
          unless badges.empty?
            draw_text(row, start_col, badges.join(' '), Color::Scheme::STATUS_WARN)
            row += 1
          end

          row += 1 # Blank line

          # Core info
          row = draw_labeled_value(row, start_col, c_width, 'ICAO', @aircraft[:icao])
          row = draw_labeled_value(row, start_col, c_width, 'Altitude', format_altitude(@aircraft[:altitude]))
          row = draw_labeled_value(row, start_col, c_width, 'Speed', format_speed(@aircraft[:speed]))
          row = draw_labeled_value(row, start_col, c_width, 'Heading', format_heading(@aircraft[:heading]))
          row = draw_labeled_value(row, start_col, c_width, 'V/Rate', format_vrate(@aircraft[:vertical_rate]))
          row = draw_labeled_value(row, start_col, c_width, 'Squawk', @aircraft[:squawk])
          row = draw_labeled_value(row, start_col, c_width, 'Distance', format_distance(@aircraft[:distance]))
          row = draw_labeled_value(row, start_col, c_width, 'Signal', format_signal(@aircraft[:signal_strength]))
          row = draw_labeled_value(row, start_col, c_width, 'Messages', @aircraft[:messages])

          # Position
          if @aircraft[:latitude] && @aircraft[:longitude]
            row += 1
            pos = format('%0.4f, %0.4f', @aircraft[:latitude], @aircraft[:longitude])
            row = draw_labeled_value(row, start_col, c_width, 'Position', pos)
          end

          # EHS data
          row = draw_ehs_section(row, start_col, c_width)

          # FAA registration
          draw_faa_section(row, start_col, c_width)
        end

        def draw_ehs_section(row, col, width)
          ehs_fields = [
            [:selected_altitude, 'Sel Alt', ->(v) { "#{v} ft" }],
            [:indicated_airspeed, 'IAS', ->(v) { "#{v} kt" }],
            [:mach, 'Mach', ->(v) { format('%.2f', v) }],
            [:magnetic_heading, 'Mag Hdg', ->(v) { "#{v.round}°" }],
            [:roll_angle, 'Roll', ->(v) { "#{v.round}°" }]
          ]

          has_ehs = ehs_fields.any? { |key, _, _| @aircraft[key] }
          return row unless has_ehs

          row += 1
          draw_text(row, col, '-- EHS Data --', Color::Scheme::DIM)
          row += 1

          ehs_fields.each do |key, label, formatter|
            value = @aircraft[key]
            next unless value

            row = draw_labeled_value(row, col, width, label, formatter.call(value))
          end

          row
        end

        def draw_faa_section(row, col, width)
          return row unless @faa_data

          row += 1
          draw_text(row, col, '-- Registration --', Color::Scheme::DIM)
          row += 1

          row = draw_labeled_value(row, col, width, 'N-Number', @faa_data[:n_number])
          row = draw_labeled_value(row, col, width, 'Type', "#{@faa_data[:manufacturer]} #{@faa_data[:model]}")
          row = draw_labeled_value(row, col, width, 'Owner', @faa_data[:owner])
          row = draw_labeled_value(row, col, width, 'Location', "#{@faa_data[:city]}, #{@faa_data[:state]}")
          draw_labeled_value(row, col, width, 'Year', @faa_data[:year])
        end

        def draw_labeled_value(row, col, width, label, value)
          return row if value.nil?

          label_width = 10
          value_str = value.to_s[0, width - label_width - 2]

          draw_text(row, col, "#{label}:", Color::Scheme::DIM)
          draw_text(row, col + label_width, value_str, Color::Scheme::DEFAULT)
          row + 1
        end

        def format_altitude(alt)
          alt ? "#{alt} ft" : nil
        end

        def format_speed(spd)
          spd ? "#{spd} kt" : nil
        end

        def format_heading(hdg)
          hdg ? "#{hdg.round}°" : nil
        end

        def format_vrate(vr)
          return nil unless vr

          if vr > 0
            "+#{vr} fpm"
          elsif vr < 0
            "#{vr} fpm"
          else
            '0 fpm'
          end
        end

        def format_distance(dist)
          dist ? format('%.1f nm', dist) : nil
        end

        def format_signal(sig)
          return nil unless sig

          pct = [(sig / 0.4 * 100).round, 100].min
          "#{pct}%"
        end

        def military?
          # Delegate to filter engine if available, otherwise basic check
          icao = @aircraft[:icao].to_s
          %w[AE AF].any? { |p| icao.start_with?(p) }
        end

        def police?
          icao = @aircraft[:icao].to_s.upcase
          Data::FilterEngine::LAW_ENFORCEMENT_ICAOS.include?(icao)
        end

        def emergency?
          Color::Scheme.emergency_squawk?(@aircraft[:squawk])
        end
      end
    end
  end
end
