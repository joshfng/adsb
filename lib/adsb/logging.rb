# frozen_string_literal: true

require "logger"

module ADSB
  class << self
    attr_writer :logger

    def logger
      @logger ||= create_default_logger
    end

    def log_level=(level)
      logger.level = level
    end

    private

    def create_default_logger
      log = ::Logger.new($stdout)
      log.level = ::Logger::INFO
      log.formatter = proc do |severity, _time, _progname, msg|
        "[#{severity}] #{msg}\n"
      end
      log
    end
  end
end
