# frozen_string_literal: true

require_relative "base_window"

module ADSB
  module TUI
    module Windows
      # Modal help overlay showing all keyboard shortcuts
      class HelpOverlay < BaseWindow
        HELP_TEXT = [
          [ "Navigation", "" ],
          [ "j / ↓", "Move down" ],
          [ "k / ↑", "Move up" ],
          [ "PgDn", "Page down" ],
          [ "PgUp", "Page up" ],
          [ "Home", "Go to top" ],
          [ "End", "Go to bottom" ],
          [ "Enter", "Select aircraft" ],
          [ "", "" ],
          [ "Panels", "" ],
          [ "Tab", "Toggle detail/stats panel" ],
          [ "l", "Toggle log panel" ],
          [ "", "" ],
          [ "Filtering", "" ],
          [ "/", "Search by callsign/ICAO" ],
          [ "f", "Open filter dialog" ],
          [ "s", "Open sort menu" ],
          [ "1-9", "Quick sort by column" ],
          [ "", "" ],
          [ "Other", "" ],
          [ "r", "Force refresh" ],
          [ "?", "Show this help" ],
          [ "q", "Quit" ]
        ].freeze

        def initialize
          # Calculate size based on content
          width = 40
          height = HELP_TEXT.length + 4
          top = 3
          left = 10

          super(height: height, width: width, top: top, left: left, title: "Help", border: true)
        end

        def draw
          @window.clear
          draw_border
          draw_title

          start_row, start_col, _, c_width = content_area
          row = start_row

          HELP_TEXT.each do |key, desc|
            if key.empty? && desc.empty?
              row += 1
              next
            end

            if desc.empty?
              # Section header
              draw_text(row, start_col, key, Color::Scheme::HEADER, Curses::A_BOLD)
            else
              # Key binding
              draw_text(row, start_col, key.ljust(10), Color::Scheme::STATUS_OK)
              draw_text(row, start_col + 10, desc[0, c_width - 11], Color::Scheme::DEFAULT)
            end
            row += 1
          end
        end

        def handle_key(_key)
          # Any key closes the help overlay
          :close
        end
      end
    end
  end
end
