# frozen_string_literal: true

require_relative "base_window"

module ADSB
  module TUI
    module Windows
      # Sort column selection dialog
      class SortDialog < BaseWindow
        SORT_OPTIONS = [
          { key: :distance, label: "Distance", num: "1" },
          { key: :callsign, label: "Callsign", num: "2" },
          { key: :altitude, label: "Altitude", num: "3" },
          { key: :speed, label: "Speed", num: "4" },
          { key: :heading, label: "Heading", num: "5" },
          { key: :vrate, label: "V/Rate", num: "6" },
          { key: :signal, label: "Signal", num: "7" },
          { key: :age, label: "Age", num: "8" },
          { key: :icao, label: "ICAO", num: "9" }
        ].freeze

        def initialize(filter_engine:)
          width = 25
          height = SORT_OPTIONS.length + 5
          top = 5
          left = 25

          super(height: height, width: width, top: top, left: left, title: "Sort By", border: true)
          @filter_engine = filter_engine
          @selected_index = find_current_index
        end

        def draw
          @window.clear
          draw_border
          draw_title

          start_row, start_col, _, c_width = content_area
          row = start_row

          SORT_OPTIONS.each_with_index do |opt, idx|
            selected = idx == @selected_index
            current = @filter_engine.sort_key == opt[:key]

            draw_option(row, start_col, c_width, opt, selected, current)
            row += 1
          end

          # Direction indicator
          row += 1
          direction = @filter_engine.sort_ascending ? "Ascending" : "Descending"
          draw_text(row, start_col, "Order: #{direction}", Color::Scheme::DIM)
          row += 1
          draw_text(row, start_col, "Tab: toggle order", Color::Scheme::DIM)
        end

        def handle_key(key)
          case key
          when "j", Curses::Key::DOWN
            @selected_index = (@selected_index + 1) % SORT_OPTIONS.length
            :update
          when "k", Curses::Key::UP
            @selected_index = (@selected_index - 1) % SORT_OPTIONS.length
            :update
          when 10, 13, Curses::Key::ENTER
            apply_selection
            :close
          when 9 # Tab
            @filter_engine.sort_ascending = !@filter_engine.sort_ascending
            :update
          when 27, "q" # Escape
            :close
          when "1".."9"
            idx = key.to_i - 1
            if idx < SORT_OPTIONS.length
              @selected_index = idx
              apply_selection
              :close
            end
          end
        end

        private

        def draw_option(row, col, width, opt, selected, current)
          attrs = selected ? Curses::A_REVERSE : 0
          marker = current ? "*" : " "
          text = "#{opt[:num]}. #{marker}#{opt[:label]}"

          @window.setpos(row, col)
          @window.attron(attrs)
          @window.addstr(text.ljust(width - 1)[0, width - 1])
          @window.attroff(attrs)
        end

        def find_current_index
          current_key = @filter_engine.sort_key
          SORT_OPTIONS.find_index { |opt| opt[:key] == current_key } || 0
        end

        def apply_selection
          opt = SORT_OPTIONS[@selected_index]
          @filter_engine.sort_key = opt[:key]
        end
      end
    end
  end
end
