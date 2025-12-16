# frozen_string_literal: true

require_relative "../curses_compat"

module ADSB
  module TUI
    module Color
      # Color pair definitions for the TUI
      module Scheme
        # Color pair constants
        DEFAULT = 1
        ALT_LOW = 2        # <10k ft - Green
        ALT_MID_LOW = 3    # 10-20k ft - Yellow
        ALT_MID = 4        # 20-30k ft - Orange (yellow fallback)
        ALT_MID_HIGH = 5   # 30-40k ft - Red
        ALT_HIGH = 6       # >40k ft - Magenta
        EMERGENCY = 7      # White on Red background
        MILITARY = 8       # Green text
        POLICE = 9         # Cyan text
        HEADER = 10        # Cyan text for headers
        SELECTED = 11      # Reverse video handled separately
        STATUS_OK = 12     # Green
        STATUS_WARN = 13   # Yellow
        STATUS_ERROR = 14  # Red
        BORDER = 15        # Border color
        DIM = 16           # Dim/muted text

        class << self
          def init!
            return unless Curses.has_colors?

            Curses.start_color
            Curses.use_default_colors

            # -1 uses terminal default background
            Curses.init_pair(DEFAULT, Curses::COLOR_WHITE, -1)

            # Altitude colors (matching web GUI bands)
            Curses.init_pair(ALT_LOW, Curses::COLOR_GREEN, -1)
            Curses.init_pair(ALT_MID_LOW, Curses::COLOR_YELLOW, -1)
            Curses.init_pair(ALT_MID, Curses::COLOR_YELLOW, -1)  # Orange not in 8-color
            Curses.init_pair(ALT_MID_HIGH, Curses::COLOR_RED, -1)
            Curses.init_pair(ALT_HIGH, Curses::COLOR_MAGENTA, -1)

            # Special categories
            Curses.init_pair(EMERGENCY, Curses::COLOR_WHITE, Curses::COLOR_RED)
            Curses.init_pair(MILITARY, Curses::COLOR_GREEN, -1)
            Curses.init_pair(POLICE, Curses::COLOR_CYAN, -1)

            # UI elements
            Curses.init_pair(HEADER, Curses::COLOR_CYAN, -1)
            Curses.init_pair(STATUS_OK, Curses::COLOR_GREEN, -1)
            Curses.init_pair(STATUS_WARN, Curses::COLOR_YELLOW, -1)
            Curses.init_pair(STATUS_ERROR, Curses::COLOR_RED, -1)
            Curses.init_pair(BORDER, Curses::COLOR_BLUE, -1)
            Curses.init_pair(DIM, Curses::COLOR_WHITE, -1)
          end

          # Get color pair for altitude
          def altitude_color(altitude)
            return DEFAULT unless altitude

            case altitude
            when 0...10_000      then ALT_LOW
            when 10_000...20_000 then ALT_MID_LOW
            when 20_000...30_000 then ALT_MID
            when 30_000...40_000 then ALT_MID_HIGH
            else                      ALT_HIGH
            end
          end

          # Check if squawk is emergency
          def emergency_squawk?(squawk)
            %w[7500 7600 7700].include?(squawk.to_s)
          end
        end
      end
    end
  end
end
