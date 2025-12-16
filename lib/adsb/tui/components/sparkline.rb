# frozen_string_literal: true

module ADSB
  module TUI
    module Components
      # ASCII sparkline for message rates
      class Sparkline
        CHARS = [' ', '_', '.', '-', '~', '^', '*', '#'].freeze

        def initialize(values, width: 20)
          @values = values || []
          @width = width
        end

        def render
          return ' ' * @width if @values.empty?

          # Take last N values to fit width
          data = @values.last(@width)
          return ' ' * @width if data.empty?

          # Calculate deltas (rate of change)
          deltas = []
          data.each_cons(2) do |a, b|
            deltas << (b - a)
          end

          return ' ' * @width if deltas.empty?

          # Normalize to character range
          max_delta = deltas.map(&:abs).max
          max_delta = 1 if max_delta.zero?

          deltas.map do |d|
            normalized = ((d / max_delta.to_f) + 1) / 2.0 # 0 to 1
            idx = (normalized * (CHARS.length - 1)).round
            CHARS[idx.clamp(0, CHARS.length - 1)]
          end.join
        end
      end
    end
  end
end
