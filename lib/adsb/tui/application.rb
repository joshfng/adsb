# frozen_string_literal: true

require_relative "curses_compat"
require_relative "../constants"
require_relative "../logging"
require_relative "../sdr_config"
require_relative "../sdr_receiver"
require_relative "color/scheme"
require_relative "screen"
require_relative "data/aircraft_store"
require_relative "data/filter_engine"
require_relative "input/key_handler"
require_relative "tui_logger"

module ADSB
  module TUI
    # Main TUI application - lifecycle, event loop, coordination
    class Application
      include ADSB::Constants

      attr_reader :screen, :active_dialog

      def initialize(receiver: nil, verbose: false, config: nil)
        @config = config || SDRConfig.new
        @receiver = receiver
        @verbose = verbose
        @data_store = Data::AircraftStore.new
        @filter_engine = Data::FilterEngine.new
        @screen = nil
        @key_handler = nil
        @running = false
        @needs_refresh = false
        @refresh_mutex = Mutex.new
        @last_refresh = Time.now
        @active_dialog = nil
      end

      def run
        setup_curses
        setup_screen
        setup_receiver
        setup_signals

        @running = true
        main_loop
      rescue StandardError => e
        ADSB.logger.error "TUI error: #{e.message}"
        ADSB.logger.error e.backtrace.first(10).join("\n")
        raise
      ensure
        cleanup
      end

      def shutdown
        @running = false
      end

      # Navigation
      def scroll_down
        @screen.aircraft_list.scroll_down
      end

      def scroll_up
        @screen.aircraft_list.scroll_up
      end

      def page_down
        @screen.aircraft_list.page_down
      end

      def page_up
        @screen.aircraft_list.page_up
      end

      def home
        @screen.aircraft_list.home
      end

      def end_list
        @screen.aircraft_list.end_list
      end

      # Selection
      def select_aircraft
        ac = @screen.aircraft_list.selected_aircraft
        @screen.detail_panel.set_aircraft(ac)
      end

      # Panels
      def toggle_panel
        @screen.toggle_right_panel
      end

      def toggle_log
        @screen.toggle_log_panel
      end

      # Search
      def start_search
        @screen.search_input.activate
        @key_handler.set_mode(:search)
        @screen.footer.update(mode: :search)
      end

      def cancel_search
        @screen.search_input.deactivate
        @screen.footer.update(filter_status: @filter_engine.active_filters)
      end

      def confirm_search
        @filter_engine.search_text = @screen.search_input.text
        @screen.search_input.deactivate
        @screen.footer.update(filter_status: @filter_engine.active_filters)
        update_aircraft_list
      end

      def update_search
        @filter_engine.search_text = @screen.search_input.text
        update_aircraft_list
      end

      # Dialogs
      def show_sort_dialog
        @active_dialog = Windows::SortDialog.new(filter_engine: @filter_engine)
        @screen.show_overlay(@active_dialog)
        @key_handler.set_mode(:dialog)
      end

      def show_filter_dialog
        @active_dialog = Windows::FilterDialog.new(filter_engine: @filter_engine)
        @screen.show_overlay(@active_dialog)
        @key_handler.set_mode(:dialog)
        @screen.footer.update(mode: :filter)
      end

      def close_dialog
        @screen.hide_overlay
        @active_dialog = nil
        update_aircraft_list
        @screen.footer.update(filter_status: @filter_engine.active_filters)
      end

      def refresh_dialog
        # Dialog content updated, just refresh
      end

      def show_help
        @active_dialog = Windows::HelpOverlay.new
        @screen.show_overlay(@active_dialog)
        @key_handler.set_mode(:help)
      end

      def close_help
        @screen.hide_overlay
        @active_dialog = nil
      end

      # Quick sort by column number
      def quick_sort(column_num)
        sort_keys = %i[distance callsign altitude speed heading vrate signal age icao]
        idx = column_num - 1
        return unless idx >= 0 && idx < sort_keys.length

        @filter_engine.sort_key = sort_keys[idx]
        update_aircraft_list
      end

      def force_refresh
        @refresh_mutex.synchronize { @needs_refresh = true }
      end

      private

      def setup_curses
        Curses.init_screen
        Curses.start_color if Curses.has_colors?
        Curses.cbreak
        Curses.noecho
        Curses.curs_set(0)
        Curses.stdscr.keypad(true)
        Curses.timeout = 100 # 100ms non-blocking getch

        Color::Scheme.init!
      end

      def setup_screen
        @screen = Screen.new(filter_engine: @filter_engine, show_log: @verbose)
        @key_handler = Input::KeyHandler.new(self)

        # Set up TUI logger to write to log panel when verbose
        if @verbose
          tui_logger = TUILogger.create(@screen.log_panel, level: ::Logger::DEBUG)
          ADSB.logger = tui_logger
        end
      end

      def setup_receiver
        @receiver ||= SDRReceiver.new(config: @config)

        # Register callback for aircraft updates
        @receiver.on_aircraft_update do |_aircraft|
          @refresh_mutex.synchronize { @needs_refresh = true }
        end

        @receiver.start
        ADSB.logger.info "TUI: Receiver started"
      end

      def setup_signals
        # Handle terminal resize
        Signal.trap("WINCH") do
          @refresh_mutex.synchronize { @needs_refresh = true }
        end

        # Handle interrupt gracefully
        Signal.trap("INT") do
          @running = false
        end
      end

      def main_loop
        while @running
          # Handle input (non-blocking)
          key = Curses.getch
          if key
            @key_handler.handle(key)
            # Immediate refresh after key press for responsiveness
            @screen.refresh_all
          end

          # Check if data refresh needed
          needs_refresh = @refresh_mutex.synchronize do
            result = @needs_refresh
            @needs_refresh = false
            result
          end

          # Also refresh periodically for data updates
          elapsed = Time.now - @last_refresh
          needs_refresh ||= elapsed >= TUI_REFRESH_SEC

          if needs_refresh
            update_display
            @screen.refresh_all
            @last_refresh = Time.now
          end

          # Small sleep to prevent CPU spin when no input
          sleep(0.01) unless key
        end
      end

      def update_display
        # Get data from receiver
        aircraft_list = @receiver&.aircraft_list || []
        stats = @receiver&.get_stats || {}
        history_stats = @receiver&.history&.get_stats

        # Update data store
        @data_store.update_all(aircraft_list)

        # Apply filters and sort
        filtered = @filter_engine.apply(aircraft_list)

        # Update screen components
        @screen.header.update(
          stats: stats,
          aircraft_count: filtered.length
        )

        @screen.aircraft_list.update(filtered)

        @screen.stats_panel.update_stats(
          receiver_stats: stats,
          history_stats: history_stats
        )

        @screen.footer.update(
          filter_status: @filter_engine.active_filters,
          mode: @key_handler.mode
        )

        # Update detail panel if aircraft selected
        selected = @screen.aircraft_list.selected_aircraft
        if selected
          # Find updated data for selected aircraft
          updated = filtered.find { |ac| ac[:icao] == selected[:icao] }
          @screen.detail_panel.set_aircraft(updated || selected)
        end
      end

      def update_aircraft_list
        aircraft_list = @receiver&.aircraft_list || []
        filtered = @filter_engine.apply(aircraft_list)
        @screen.aircraft_list.update(filtered)
      end

      def cleanup
        @receiver&.stop
        @screen&.close
        Curses.close_screen
        ADSB.logger.info "TUI: Shutdown complete"
      end
    end
  end
end
