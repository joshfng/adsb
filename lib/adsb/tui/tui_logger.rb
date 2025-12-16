# frozen_string_literal: true

require "logger"

module ADSB
  module TUI
    # Custom Logger IO that writes to a LogPanel
    class TUILoggerIO
      def initialize(log_panel)
        @log_panel = log_panel
      end

      def write(message)
        return 0 if message.nil? || message.strip.empty?

        @log_panel.add_line(message)
        message.length
      end

      def close
        # No-op
      end

      def flush
        # No-op
      end
    end

    # Creates a Logger that writes to the TUI log panel
    class TUILogger
      def self.create(log_panel, level: ::Logger::DEBUG)
        io = TUILoggerIO.new(log_panel)
        logger = ::Logger.new(io)
        logger.level = level
        logger.formatter = proc do |severity, _time, _progname, msg|
          "[#{severity}] #{msg}\n"
        end
        logger
      end
    end
  end
end
