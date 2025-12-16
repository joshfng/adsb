# frozen_string_literal: true

require_relative 'base_window'

module ADSB
  module TUI
    module Windows
      # Top bar showing title, status, and message rates
      class HeaderBar < BaseWindow
        def initialize(width:, top: 0, left: 0)
          super(height: 2, width: width, top: top, left: left, border: false)
          @stats = {}
          @aircraft_count = 0
        end

        def update(stats:, aircraft_count:)
          @stats = stats || {}
          @aircraft_count = aircraft_count
        end

        def draw
          @window.clear

          # Title line
          @window.setpos(0, 0)
          @window.attron(Curses::A_BOLD | Curses.color_pair(Color::Scheme::HEADER))
          @window.addstr(' ADS-B Tracker ')
          @window.attroff(Curses::A_BOLD | Curses.color_pair(Color::Scheme::HEADER))

          # Status info
          draw_status_line
        end

        private

        def draw_status_line
          msg_total = @stats[:messages_total] || 0
          msg_rate = @stats[:messages_per_second] || 0
          uptime = format_uptime(@stats[:uptime_seconds])

          status = "Aircraft: #{@aircraft_count}  |  Msgs: #{format_number(msg_total)}  |  #{msg_rate}/s  |  Up: #{uptime}"

          # Right-align status info
          x = @width - status.length - 2
          x = 20 if x < 20

          @window.setpos(0, x)
          @window.attron(Curses.color_pair(Color::Scheme::DEFAULT))
          @window.addstr(status)
          @window.attroff(Curses.color_pair(Color::Scheme::DEFAULT))

          # Separator line
          @window.setpos(1, 0)
          @window.attron(Curses.color_pair(Color::Scheme::BORDER))
          @window.addstr('-' * @width)
          @window.attroff(Curses.color_pair(Color::Scheme::BORDER))
        end

        def format_uptime(seconds)
          return '--' unless seconds

          hours = seconds / 3600
          mins = (seconds % 3600) / 60
          "#{hours}h#{mins}m"
        end

        def format_number(num)
          num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end
      end
    end
  end
end
