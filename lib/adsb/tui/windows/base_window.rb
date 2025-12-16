# frozen_string_literal: true

require_relative "../curses_compat"

module ADSB
  module TUI
    module Windows
      # Abstract base class for all TUI windows
      class BaseWindow
        attr_reader :window, :height, :width, :top, :left, :title

        def initialize(height:, width:, top:, left:, title: nil, border: true)
          @height = height
          @width = width
          @top = top
          @left = left
          @title = title
          @border = border
          @window = Curses::Window.new(height, width, top, left)
          @window.keypad(true)
        end

        def draw
          raise NotImplementedError, "#{self.class} must implement #draw"
        end

        def refresh
          @window.noutrefresh
        end

        def resize(height:, width:, top:, left:)
          @height = height
          @width = width
          @top = top
          @left = left
          @window.resize(height, width)
          @window.move(top, left)
          @window.clear
        end

        def close
          @window.close
        end

        protected

        def draw_border
          return unless @border

          @window.attron(Curses.color_pair(Color::Scheme::BORDER))
          @window.box("|", "-")
          @window.attroff(Curses.color_pair(Color::Scheme::BORDER))
        end

        def draw_title
          return unless @title && @border

          @window.setpos(0, 2)
          @window.attron(Curses::A_BOLD | Curses.color_pair(Color::Scheme::HEADER))
          @window.addstr(" #{@title} ")
          @window.attroff(Curses::A_BOLD | Curses.color_pair(Color::Scheme::HEADER))
        end

        # Returns content area dimensions [start_row, start_col, content_height, content_width]
        def content_area
          if @border
            [ 1, 1, @height - 2, @width - 2 ]
          else
            [ 0, 0, @height, @width ]
          end
        end

        def content_height
          @border ? @height - 2 : @height
        end

        def content_width
          @border ? @width - 2 : @width
        end

        # Draw text with color at position
        def draw_text(row, col, text, color_pair = Color::Scheme::DEFAULT, attrs = 0)
          @window.setpos(row, col)
          @window.attron(Curses.color_pair(color_pair) | attrs)
          @window.addstr(text)
          @window.attroff(Curses.color_pair(color_pair) | attrs)
        end

        # Draw text truncated to fit width
        def draw_text_fit(row, col, text, max_width, color_pair = Color::Scheme::DEFAULT, attrs = 0)
          truncated = text.to_s[0, max_width]
          draw_text(row, col, truncated, color_pair, attrs)
        end

        # Clear content area
        def clear_content
          start_row, start_col, c_height, c_width = content_area
          blank = " " * c_width
          c_height.times do |i|
            @window.setpos(start_row + i, start_col)
            @window.addstr(blank)
          end
        end
      end
    end
  end
end
