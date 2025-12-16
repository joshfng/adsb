# frozen_string_literal: true

require "concurrent"

# Load ADSB library from lib/adsb
adsb_lib_path = Rails.root.join("lib", "adsb")

require adsb_lib_path.join("constants")
require adsb_lib_path.join("logging")
require adsb_lib_path.join("sdr_config")
require adsb_lib_path.join("adsb_decoder")
require adsb_lib_path.join("adsb_demodulator")
require adsb_lib_path.join("sdr_receiver")
require adsb_lib_path.join("flight_history")
require adsb_lib_path.join("faa_lookup")

# Set log level (can be overridden with ADSB_LOG_LEVEL env var)
log_level = ENV.fetch("ADSB_LOG_LEVEL", "INFO").upcase
ADSB.log_level = Logger.const_get(log_level) rescue Logger::INFO

# ADSB Service Singleton
# Provides access to receiver and lookup services throughout the app
module AdsbService
  class << self
    attr_accessor :receiver, :sdr_config, :faa_lookup, :mutex
    attr_reader :broadcast_task

    def initialize!
      @mutex = Mutex.new
      @faa_lookup = FAALookup.new
      @sdr_config = nil
      @receiver = nil
      @broadcast_task = nil
    end

    def start_receiver
      return if @receiver&.running

      @mutex.synchronize do
        @sdr_config ||= SDRConfig.from_env
        @receiver ||= SDRReceiver.new(config: @sdr_config)

        @receiver.on_aircraft_update do |aircraft|
          broadcast_aircraft_update(aircraft)
        end

        @receiver.start
        ADSB.logger.info "Receiver started"
      end
    end

    def stop_receiver
      @mutex.synchronize do
        @receiver&.stop
        ADSB.logger.info "Receiver stopped"
      end
    end

    def shutdown!
      @broadcast_task&.shutdown
      stop_receiver
    end

    def start_broadcast_task
      return if @broadcast_task&.running?

      @broadcast_task = Concurrent::TimerTask.new(
        execution_interval: ADSB::Constants::WEBSOCKET_BROADCAST_SEC,
        run_now: false
      ) do
        broadcast_aircraft_list
      end

      @broadcast_task.add_observer do |_time, _result, error|
        ADSB.logger.error "Broadcast task error: #{error}" if error
      end

      @broadcast_task.execute
      ADSB.logger.info "Broadcast task started"
    end

    def broadcast_aircraft_update(aircraft)
      # Broadcast via ActionCable if available
      ActionCable.server.broadcast("aircraft", { type: "aircraft_update", aircraft: aircraft })
    rescue StandardError => e
      ADSB.logger.warn "Failed to broadcast aircraft update: #{e.message}"
    end

    def broadcast_aircraft_list
      return unless @receiver&.running

      aircraft_list = @receiver.aircraft_list
      ActionCable.server.broadcast("aircraft", { type: "aircraft_list", aircraft: aircraft_list })
    rescue StandardError => e
      ADSB.logger.warn "Failed to broadcast aircraft list: #{e.message}"
    end
  end
end

# Initialize service
AdsbService.initialize!

# Register shutdown hook for clean termination
at_exit do
  AdsbService.shutdown!
end

# Auto-start receiver on server start (unless disabled)
Rails.application.config.after_initialize do
  if ENV["ADSB_AUTO_START"] != "false" && !Rails.env.test?
    # Start receiver after a short delay to let server fully initialize
    Concurrent::ScheduledTask.execute(1) do
      begin
        AdsbService.start_receiver
        AdsbService.start_broadcast_task
      rescue StandardError => e
        ADSB.logger.error "Failed to start receiver: #{e.message}"
        ADSB.logger.error e.backtrace.first(5).join("\n")
      end
    end
  end
end
