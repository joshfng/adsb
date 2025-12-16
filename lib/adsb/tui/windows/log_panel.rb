# frozen_string_literal: true

require_relative 'base_window'

module ADSB
  module TUI
    module Windows
      # Scrollable log panel showing recent log messages
      class LogPanel < BaseWindow
        MAX_LINES = 500 # Keep last N log lines in memory

        attr_accessor :visible

        def initialize(height:, width:, top:, left:)
          super(height: height, width: width, top: top, left: left, title: 'Log', border: true)
          @lines = []
          @scroll_offset = 0
          @auto_scroll = true
          @visible = false
        end

        def add_line(line)
          # Strip ANSI codes and truncate
          clean_line = line.to_s.gsub(/\e\[[0-9;]*m/, '').chomp
          @lines << clean_line
          @lines.shift while @lines.length > MAX_LINES

          # Auto-scroll to bottom
          @scroll_offset = max_scroll if @auto_scroll
        end

        def draw
          return unless @visible

          @window.clear
          draw_border
          draw_title

          start_row, start_col, c_height, c_width = content_area
          visible_lines = c_height

          # Get lines to display
          display_lines = @lines[@scroll_offset, visible_lines] || []

          display_lines.each_with_index do |line, idx|
            @window.setpos(start_row + idx, start_col)

            # Color based on log level
            color = color_for_line(line)
            @window.attron(Curses.color_pair(color))
            @window.addstr(line[0, c_width - 1] || '')
            @window.attroff(Curses.color_pair(color))
          end

          # Scroll indicator
          draw_scroll_indicator
        end

        def scroll_up
          @auto_scroll = false
          @scroll_offset = [@scroll_offset - 1, 0].max
        end

        def scroll_down
          @scroll_offset = [@scroll_offset + 1, max_scroll].min
          @auto_scroll = (@scroll_offset >= max_scroll)
        end

        def page_up
          @auto_scroll = false
          _, _, c_height, _ = content_area
          @scroll_offset = [@scroll_offset - c_height, 0].max
        end

        def page_down
          _, _, c_height, _ = content_area
          @scroll_offset = [@scroll_offset + c_height, max_scroll].min
          @auto_scroll = (@scroll_offset >= max_scroll)
        end

        def scroll_to_bottom
          @scroll_offset = max_scroll
          @auto_scroll = true
        end

        def clear_log
          @lines.clear
          @scroll_offset = 0
        end

        private

        def max_scroll
          _, _, c_height, _ = content_area
          [@lines.length - c_height, 0].max
        end

        def color_for_line(line)
          case line
          when /^\[ERROR\]/i, /error/i
            Color::Scheme::STATUS_ERROR
          when /^\[WARN\]/i, /warning/i
            Color::Scheme::STATUS_WARN
          when /^\[DEBUG\]/i
            Color::Scheme::DIM
          else
            Color::Scheme::DEFAULT
          end
        end

        def draw_scroll_indicator
          return if @lines.empty?

          _, _, c_height, _ = content_area
          return if @lines.length <= c_height

          # Show scroll position in title area
          total = @lines.length
          pos = @scroll_offset + 1
          indicator = @auto_scroll ? '[AUTO]' : "[#{pos}/#{total}]"

          @window.setpos(0, @width - indicator.length - 3)
          @window.attron(Curses.color_pair(Color::Scheme::DIM))
          @window.addstr(indicator)
          @window.attroff(Curses.color_pair(Color::Scheme::DIM))
        end
      end
    end
  end
end
