# frozen_string_literal: true

require_relative "base_window"
require_relative "../components/sparkline"

module ADSB
  module TUI
    module Windows
      # Statistics panel showing receiver and history stats
      class StatsPanel < BaseWindow
        def initialize(height:, width:, top:, left:)
          super(height: height, width: width, top: top, left: left, title: "Statistics", border: true)
          @receiver_stats = {}
          @history_stats = {}
          @message_history = []
        end

        def update_stats(receiver_stats:, history_stats: nil)
          @receiver_stats = receiver_stats || {}
          @history_stats = history_stats || {}

          # Track message count for sparkline
          msg_total = @receiver_stats[:messages_total]
          if msg_total
            @message_history << msg_total
            @message_history = @message_history.last(60)
          end
        end

        def draw
          @window.clear
          draw_border
          draw_title

          start_row, start_col, _, c_width = content_area
          row = start_row

          # Receiver section
          draw_text(row, start_col, "-- Receiver --", Color::Scheme::DIM)
          row += 1

          row = draw_stat(row, start_col, c_width, "Frequency", format_freq(@receiver_stats[:frequency]))
          row = draw_stat(row, start_col, c_width, "Sample Rate", format_rate(@receiver_stats[:sample_rate]))
          row = draw_stat(row, start_col, c_width, "Gain", format_gain(@receiver_stats[:gain]))
          row = draw_stat(row, start_col, c_width, "Uptime", format_uptime(@receiver_stats[:uptime_seconds]))

          row += 1

          # Message stats
          draw_text(row, start_col, "-- Messages --", Color::Scheme::DIM)
          row += 1

          row = draw_stat(row, start_col, c_width, "Total", format_number(@receiver_stats[:messages_total]))
          row = draw_stat(row, start_col, c_width, "Position", format_number(@receiver_stats[:messages_position]))
          row = draw_stat(row, start_col, c_width, "Velocity", format_number(@receiver_stats[:messages_velocity]))
          row = draw_stat(row, start_col, c_width, "Ident", format_number(@receiver_stats[:messages_identification]))
          row = draw_stat(row, start_col, c_width, "Preambles", format_number(@receiver_stats[:preambles_detected]))
          row = draw_stat(row, start_col, c_width, "CRC Fails", format_number(@receiver_stats[:crc_failures]))

          # Message rate sparkline
          row += 1
          sparkline = Components::Sparkline.new(@message_history, width: c_width - 8)
          draw_text(row, start_col, "Rate:", Color::Scheme::DIM)
          draw_text(row, start_col + 6, sparkline.render, Color::Scheme::HEADER)

          row += 2

          # History section (if available)
          return unless @history_stats && !@history_stats.empty?

          draw_text(row, start_col, "-- History --", Color::Scheme::DIM)
          row += 1

          row = draw_stat(row, start_col, c_width, "Aircraft Today", @history_stats[:aircraft_today])
          row = draw_stat(row, start_col, c_width, "Total Aircraft", @history_stats[:total_aircraft_seen])
          row = draw_stat(row, start_col, c_width, "Sightings Today", format_number(@history_stats[:sightings_today]))
          draw_stat(row, start_col, c_width, "Total Sightings", format_number(@history_stats[:sightings_total]))
        end

        private

        def draw_stat(row, col, width, label, value)
          return row if value.nil?

          label_width = 14
          value_str = value.to_s[0, width - label_width - 1]

          draw_text(row, col, "#{label}:", Color::Scheme::DIM)
          draw_text(row, col + label_width, value_str, Color::Scheme::DEFAULT)
          row + 1
        end

        def format_freq(freq)
          return nil unless freq

          mhz = freq / 1_000_000.0
          "#{mhz} MHz"
        end

        def format_rate(rate)
          return nil unless rate

          mhz = rate / 1_000_000.0
          "#{mhz} MS/s"
        end

        def format_gain(gain)
          return nil unless gain

          "#{gain} dB"
        end

        def format_uptime(seconds)
          return nil unless seconds

          hours = seconds / 3600
          mins = (seconds % 3600) / 60
          secs = seconds % 60
          format("%02d:%02d:%02d", hours, mins, secs)
        end

        def format_number(num)
          return nil unless num

          num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end
      end
    end
  end
end
