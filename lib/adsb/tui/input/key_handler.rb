# frozen_string_literal: true

require_relative "../curses_compat"

module ADSB
  module TUI
    module Input
      # Keyboard input handler with mode-based dispatch
      class KeyHandler
        attr_reader :mode

        def initialize(app)
          @app = app
          @mode = :normal
        end

        def set_mode(mode)
          @mode = mode
        end

        def handle(key)
          return if key.nil?

          case @mode
          when :normal
            handle_normal(key)
          when :search
            handle_search(key)
          when :dialog
            handle_dialog(key)
          when :help
            handle_help(key)
          end
        end

        private

        def handle_normal(key)
          case key
          when "q", "Q"
            @app.shutdown
          when "j", Curses::Key::DOWN
            @app.scroll_down
          when "k", Curses::Key::UP
            @app.scroll_up
          when Curses::Key::NPAGE # Page Down
            @app.page_down
          when Curses::Key::PPAGE # Page Up
            @app.page_up
          when Curses::Key::HOME
            @app.home
          when Curses::KEY_END
            @app.end_list
          when 10, 13, Curses::Key::ENTER
            @app.select_aircraft
          when 9 # Tab
            @app.toggle_panel
          when "s", "S"
            @app.show_sort_dialog
          when "/"
            @app.start_search
          when "f", "F"
            @app.show_filter_dialog
          when "r", "R"
            @app.force_refresh
          when "?"
            @app.show_help
          when "l", "L"
            @app.toggle_log
          when "1".."9"
            @app.quick_sort(key.to_i)
          end
        end

        def handle_search(key)
          result = @app.screen.search_input.handle_key(key)

          case result
          when :cancel
            @app.cancel_search
            @mode = :normal
          when :confirm
            @app.confirm_search
            @mode = :normal
          when :update
            @app.update_search
          end
        end

        def handle_dialog(key)
          result = @app.active_dialog&.handle_key(key)

          case result
          when :close
            @app.close_dialog
            @mode = :normal
          when :update
            @app.refresh_dialog
          end
        end

        def handle_help(key)
          # Any key closes help
          @app.close_help
          @mode = :normal
        end
      end
    end
  end
end
