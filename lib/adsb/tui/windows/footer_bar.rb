# frozen_string_literal: true

require_relative "base_window"

module ADSB
  module TUI
    module Windows
      # Bottom bar showing key hints and filter status
      class FooterBar < BaseWindow
        HINTS = "q:Quit  j/k:Nav  Enter:Select  Tab:Panel  /:Search  s:Sort  f:Filter  l:Log  ?:Help"

        def initialize(width:, top:, left: 0)
          super(height: 2, width: width, top: top, left: left, border: false)
          @filter_status = ""
          @mode = :normal
        end

        def update(filter_status: "", mode: :normal)
          @filter_status = filter_status
          @mode = mode
        end

        def draw
          @window.clear

          # Separator line
          @window.setpos(0, 0)
          @window.attron(Curses.color_pair(Color::Scheme::BORDER))
          @window.addstr("-" * @width)
          @window.attroff(Curses.color_pair(Color::Scheme::BORDER))

          # Key hints or filter status
          @window.setpos(1, 1)

          case @mode
          when :search
            draw_search_mode
          when :filter
            draw_filter_mode
          else
            draw_normal_mode
          end
        end

        private

        def draw_normal_mode
          # Show filter status if active, otherwise show hints
          if @filter_status.empty?
            @window.attron(Curses.color_pair(Color::Scheme::DIM))
            @window.addstr(HINTS[0, @width - 2])
            @window.attroff(Curses.color_pair(Color::Scheme::DIM))
          else
            @window.attron(Curses.color_pair(Color::Scheme::STATUS_WARN))
            @window.addstr("Filter: #{@filter_status}"[0, @width - 2])
            @window.attroff(Curses.color_pair(Color::Scheme::STATUS_WARN))
          end
        end

        def draw_search_mode
          @window.attron(Curses.color_pair(Color::Scheme::HEADER))
          @window.addstr("Search mode - Type to filter, Enter to confirm, Esc to cancel")
          @window.attroff(Curses.color_pair(Color::Scheme::HEADER))
        end

        def draw_filter_mode
          @window.attron(Curses.color_pair(Color::Scheme::HEADER))
          @window.addstr("Filter dialog - Use Tab to navigate, Enter to toggle, Esc to close")
          @window.attroff(Curses.color_pair(Color::Scheme::HEADER))
        end
      end
    end
  end
end
