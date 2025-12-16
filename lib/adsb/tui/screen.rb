# frozen_string_literal: true

require_relative 'curses_compat'
require_relative 'color/scheme'
require_relative 'windows/header_bar'
require_relative 'windows/footer_bar'
require_relative 'windows/aircraft_list'
require_relative 'windows/detail_panel'
require_relative 'windows/stats_panel'
require_relative 'windows/search_input'
require_relative 'windows/help_overlay'
require_relative 'windows/filter_dialog'
require_relative 'windows/sort_dialog'
require_relative 'windows/log_panel'

module ADSB
  module TUI
    # Screen layout manager - creates and positions all windows
    class Screen
      HEADER_HEIGHT = 2
      FOOTER_HEIGHT = 2
      LOG_PANEL_HEIGHT = 8
      LEFT_PANE_RATIO = 0.6
      MIN_WIDTH = 80
      MIN_HEIGHT = 20

      attr_reader :header, :footer, :aircraft_list, :detail_panel, :stats_panel
      attr_reader :search_input, :active_right_panel, :log_panel

      def initialize(filter_engine:, show_log: false)
        @filter_engine = filter_engine
        @active_right_panel = :detail
        @overlay = nil
        @show_log = show_log

        create_windows
      end

      def layout!
        lines = Curses.lines
        cols = Curses.cols

        # Enforce minimum size
        lines = MIN_HEIGHT if lines < MIN_HEIGHT
        cols = MIN_WIDTH if cols < MIN_WIDTH

        # Calculate heights based on log panel visibility
        log_height = @log_panel.visible ? LOG_PANEL_HEIGHT : 0
        content_height = lines - HEADER_HEIGHT - FOOTER_HEIGHT - log_height
        left_width = (cols * LEFT_PANE_RATIO).to_i
        right_width = cols - left_width

        # Resize all windows
        @header.resize(height: HEADER_HEIGHT, width: cols, top: 0, left: 0)
        @footer.resize(height: FOOTER_HEIGHT, width: cols, top: lines - FOOTER_HEIGHT, left: 0)

        @aircraft_list.resize(
          height: content_height,
          width: left_width,
          top: HEADER_HEIGHT,
          left: 0
        )

        @detail_panel.resize(
          height: content_height,
          width: right_width,
          top: HEADER_HEIGHT,
          left: left_width
        )

        @stats_panel.resize(
          height: content_height,
          width: right_width,
          top: HEADER_HEIGHT,
          left: left_width
        )

        @search_input.resize(
          height: 1,
          width: cols,
          top: lines - FOOTER_HEIGHT - 1,
          left: 0
        )

        # Log panel at bottom (above footer)
        @log_panel.resize(
          height: LOG_PANEL_HEIGHT,
          width: cols,
          top: lines - FOOTER_HEIGHT - LOG_PANEL_HEIGHT,
          left: 0
        )
      end

      def toggle_right_panel
        @active_right_panel = @active_right_panel == :detail ? :stats : :detail
      end

      def toggle_log_panel
        @log_panel.visible = !@log_panel.visible
        layout! # Recalculate layout
      end

      def log_visible?
        @log_panel.visible
      end

      def show_overlay(overlay)
        @overlay = overlay
      end

      def hide_overlay
        @overlay = nil
      end

      def refresh_all
        # Draw all windows
        @header.draw
        @footer.draw
        @aircraft_list.draw

        if @active_right_panel == :detail
          @detail_panel.draw
        else
          @stats_panel.draw
        end

        @log_panel.draw if @log_panel.visible
        @search_input.draw if @search_input.active

        # Draw overlay on top if present
        @overlay&.draw

        # Mark for refresh
        @header.refresh
        @footer.refresh
        @aircraft_list.refresh

        if @active_right_panel == :detail
          @detail_panel.refresh
        else
          @stats_panel.refresh
        end

        @log_panel.refresh if @log_panel.visible
        @search_input.refresh if @search_input.active
        @overlay&.refresh

        # Single screen update
        Curses.doupdate
      end

      def close
        @header.close
        @footer.close
        @aircraft_list.close
        @detail_panel.close
        @stats_panel.close
        @log_panel.close
        @search_input.close
        @overlay&.close
      end

      private

      def create_windows
        lines = Curses.lines
        cols = Curses.cols

        # Log panel created first but may not be visible
        @log_panel = Windows::LogPanel.new(
          height: LOG_PANEL_HEIGHT,
          width: cols,
          top: lines - FOOTER_HEIGHT - LOG_PANEL_HEIGHT,
          left: 0
        )
        @log_panel.visible = @show_log

        log_height = @log_panel.visible ? LOG_PANEL_HEIGHT : 0
        content_height = lines - HEADER_HEIGHT - FOOTER_HEIGHT - log_height
        left_width = (cols * LEFT_PANE_RATIO).to_i
        right_width = cols - left_width

        @header = Windows::HeaderBar.new(
          width: cols,
          top: 0,
          left: 0
        )

        @footer = Windows::FooterBar.new(
          width: cols,
          top: lines - FOOTER_HEIGHT,
          left: 0
        )

        @aircraft_list = Windows::AircraftList.new(
          height: content_height,
          width: left_width,
          top: HEADER_HEIGHT,
          left: 0,
          filter_engine: @filter_engine
        )

        @detail_panel = Windows::DetailPanel.new(
          height: content_height,
          width: right_width,
          top: HEADER_HEIGHT,
          left: left_width
        )

        @stats_panel = Windows::StatsPanel.new(
          height: content_height,
          width: right_width,
          top: HEADER_HEIGHT,
          left: left_width
        )

        @search_input = Windows::SearchInput.new(
          width: cols,
          top: lines - FOOTER_HEIGHT - 1,
          left: 0
        )
      end
    end
  end
end
