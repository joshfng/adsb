# frozen_string_literal: true

require_relative "base_window"
require_relative "../color/scheme"

module ADSB
  module TUI
    module Windows
      # Scrollable aircraft list with sorting and selection
      class AircraftList < BaseWindow
        COLUMNS = [
          { key: :icao,          label: "ICAO",   width: 7 },
          { key: :callsign,      label: "Call",   width: 8 },
          { key: :altitude,      label: "Alt",    width: 7 },
          { key: :speed,         label: "Spd",    width: 5 },
          { key: :heading,       label: "Hdg",    width: 4 },
          { key: :distance,      label: "Dist",   width: 6 },
          { key: :vertical_rate, label: "VRate",  width: 6 },
          { key: :squawk,        label: "Sqwk",   width: 5 },
          { key: :signal,        label: "Sig",    width: 4 },
          { key: :age,           label: "Age",    width: 4 }
        ].freeze

        attr_reader :selected_index, :aircraft

        def initialize(height:, width:, top:, left:, filter_engine: nil)
          super(height: height, width: width, top: top, left: left, title: "Aircraft", border: true)
          @scroll_offset = 0
          @selected_index = 0
          @aircraft = []
          @filter_engine = filter_engine
        end

        def update(aircraft_list)
          @aircraft = aircraft_list || []
          clamp_selection
        end

        def draw
          @window.clear
          draw_border
          draw_title
          draw_header_row
          draw_aircraft_rows
          draw_scrollbar if @aircraft.length > visible_rows
        end

        def scroll_up
          return if @aircraft.empty?

          @selected_index = [ @selected_index - 1, 0 ].max
          adjust_scroll
        end

        def scroll_down
          return if @aircraft.empty?

          @selected_index = [ @selected_index + 1, @aircraft.length - 1 ].min
          adjust_scroll
        end

        def page_up
          return if @aircraft.empty?

          @selected_index = [ @selected_index - visible_rows, 0 ].max
          adjust_scroll
        end

        def page_down
          return if @aircraft.empty?

          @selected_index = [ @selected_index + visible_rows, @aircraft.length - 1 ].min
          adjust_scroll
        end

        def home
          @selected_index = 0
          adjust_scroll
        end

        def end_list
          @selected_index = [ @aircraft.length - 1, 0 ].max
          adjust_scroll
        end

        def selected_aircraft
          return nil if @aircraft.empty?

          @aircraft[@selected_index]
        end

        private

        def visible_rows
          content_height - 1 # Minus header row
        end

        def draw_header_row
          start_row, start_col, _, c_width = content_area
          @window.setpos(start_row, start_col)

          @window.attron(Curses::A_BOLD | Curses.color_pair(Color::Scheme::HEADER))

          x = 0
          COLUMNS.each do |col|
            break if x + col[:width] > c_width

            @window.setpos(start_row, start_col + x)
            @window.addstr(col[:label].ljust(col[:width]))
            x += col[:width] + 1
          end

          @window.attroff(Curses::A_BOLD | Curses.color_pair(Color::Scheme::HEADER))
        end

        def draw_aircraft_rows
          start_row, start_col, _, c_width = content_area
          rows = visible_rows

          rows.times do |i|
            row_num = start_row + 1 + i
            aircraft_idx = @scroll_offset + i

            @window.setpos(row_num, start_col)
            @window.addstr(" " * (c_width - 1)) # Clear row

            next if aircraft_idx >= @aircraft.length

            ac = @aircraft[aircraft_idx]
            draw_aircraft_row(row_num, start_col, c_width, ac, aircraft_idx == @selected_index)
          end
        end

        def draw_aircraft_row(row, col, max_width, ac, selected)
          # Determine color based on type and altitude
          color = determine_row_color(ac)
          attrs = selected ? Curses::A_REVERSE : 0

          # Special markers
          markers = []
          markers << "*" if @filter_engine&.military?(ac)
          markers << "^" if @filter_engine&.police?(ac)
          markers << "!" if Color::Scheme.emergency_squawk?(ac[:squawk])
          marker_str = markers.join

          @window.setpos(row, col)
          @window.attron(Curses.color_pair(color) | attrs)

          x = 0
          COLUMNS.each do |column|
            break if x + column[:width] > max_width - 1

            value = format_column(ac, column[:key])
            @window.setpos(row, col + x)

            # Add markers to first column
            if column[:key] == :icao && !marker_str.empty?
              value = "#{marker_str}#{value}"[0, column[:width]]
            end

            @window.addstr(value.ljust(column[:width])[0, column[:width]])
            x += column[:width] + 1
          end

          @window.attroff(Curses.color_pair(color) | attrs)
        end

        def determine_row_color(ac)
          squawk = ac[:squawk].to_s
          return Color::Scheme::EMERGENCY if Color::Scheme.emergency_squawk?(squawk)
          return Color::Scheme::MILITARY if @filter_engine&.military?(ac)
          return Color::Scheme::POLICE if @filter_engine&.police?(ac)

          Color::Scheme.altitude_color(ac[:altitude])
        end

        def format_column(ac, key)
          case key
          when :icao
            ac[:icao] || "--"
          when :callsign
            ac[:callsign] || "--"
          when :altitude
            ac[:altitude] ? "#{ac[:altitude]}" : "--"
          when :speed
            ac[:speed] ? "#{ac[:speed]}" : "--"
          when :heading
            ac[:heading] ? "#{ac[:heading].round}" : "--"
          when :distance
            ac[:distance] ? format("%.1f", ac[:distance]) : "--"
          when :vertical_rate
            format_vrate(ac[:vertical_rate])
          when :squawk
            ac[:squawk] || "--"
          when :signal
            format_signal(ac[:signal_strength])
          when :age
            format_age(ac[:last_seen])
          else
            "--"
          end
        end

        def format_vrate(vrate)
          return "--" unless vrate

          if vrate > 0
            "+#{vrate}"[0, 5]
          elsif vrate < 0
            vrate.to_s[0, 5]
          else
            "0"
          end
        end

        def format_signal(strength)
          return "--" unless strength

          # Convert to percentage (max around 0.4)
          pct = [ (strength / 0.4 * 100).round, 100 ].min
          "#{pct}%"
        end

        def format_age(last_seen)
          return "--" unless last_seen

          age = Time.now - last_seen
          if age < 60
            "#{age.to_i}s"
          else
            "#{(age / 60).to_i}m"
          end
        end

        def draw_scrollbar
          return if @aircraft.empty?

          start_row, _, c_height, c_width = content_area
          bar_height = c_height - 1 # Minus header
          return if bar_height < 3

          # Calculate scrollbar position
          total = @aircraft.length
          visible = visible_rows
          return if total <= visible

          bar_size = [ (bar_height * visible / total.to_f).ceil, 1 ].max
          bar_pos = (bar_height * @scroll_offset / total.to_f).round

          bar_col = @width - 2
          bar_height.times do |i|
            @window.setpos(start_row + 1 + i, bar_col)
            if i >= bar_pos && i < bar_pos + bar_size
              @window.attron(Curses.color_pair(Color::Scheme::HEADER))
              @window.addstr("|")
              @window.attroff(Curses.color_pair(Color::Scheme::HEADER))
            else
              @window.addstr(":")
            end
          end
        end

        def clamp_selection
          return if @aircraft.empty?

          @selected_index = @selected_index.clamp(0, @aircraft.length - 1)
          adjust_scroll
        end

        def adjust_scroll
          rows = visible_rows
          return if rows <= 0

          # Scroll up if selection above viewport
          @scroll_offset = @selected_index if @selected_index < @scroll_offset

          # Scroll down if selection below viewport
          if @selected_index >= @scroll_offset + rows
            @scroll_offset = @selected_index - rows + 1
          end

          # Clamp scroll offset
          max_offset = [ @aircraft.length - rows, 0 ].max
          @scroll_offset = @scroll_offset.clamp(0, max_offset)
        end
      end
    end
  end
end
