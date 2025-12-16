# frozen_string_literal: true

require_relative "base_window"

module ADSB
  module TUI
    module Windows
      # Search input bar for filtering by callsign/ICAO
      class SearchInput < BaseWindow
        attr_reader :text, :active

        def initialize(width:, top:, left: 0)
          super(height: 1, width: width, top: top, left: left, border: false)
          @text = ""
          @cursor_pos = 0
          @active = false
        end

        def activate
          @active = true
          @text = ""
          @cursor_pos = 0
          Curses.curs_set(1) # Show cursor
        end

        def deactivate
          @active = false
          Curses.curs_set(0) # Hide cursor
        end

        def draw
          @window.clear
          @window.setpos(0, 0)

          @window.attron(Curses.color_pair(Color::Scheme::HEADER))
          @window.addstr("Search: ")
          @window.attroff(Curses.color_pair(Color::Scheme::HEADER))

          @window.addstr(@text[0, @width - 10])

          # Position cursor
          @window.setpos(0, 8 + @cursor_pos) if @active
        end

        def handle_key(key)
          case key
          when 27 # Escape
            deactivate
            :cancel
          when 10, 13, Curses::Key::ENTER # Enter
            deactivate
            :confirm
          when 127, Curses::Key::BACKSPACE # Backspace
            if @cursor_pos.positive?
              @text = @text[0...(@cursor_pos - 1)] + @text[@cursor_pos..]
              @cursor_pos -= 1
            end
            :update
          when Curses::Key::DC # Delete
            @text = @text[0...@cursor_pos] + @text[(@cursor_pos + 1)..]
            :update
          when Curses::Key::LEFT
            @cursor_pos = [ @cursor_pos - 1, 0 ].max
            :move
          when Curses::Key::RIGHT
            @cursor_pos = [ @cursor_pos + 1, @text.length ].min
            :move
          when Curses::Key::HOME
            @cursor_pos = 0
            :move
          when Curses::KEY_END
            @cursor_pos = @text.length
            :move
          when String
            # Printable character
            if key.length == 1 && key.ord >= 32
              @text = @text[0...@cursor_pos] + key + @text[@cursor_pos..]
              @cursor_pos += 1
              :update
            end
          when Integer
            # Printable character as integer
            if key >= 32 && key < 127
              char = key.chr
              @text = @text[0...@cursor_pos] + char + @text[@cursor_pos..]
              @cursor_pos += 1
              :update
            end
          end
        end

        def clear_text
          @text = ""
          @cursor_pos = 0
        end
      end
    end
  end
end
