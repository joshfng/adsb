# frozen_string_literal: true

# Centralized constants for ADS-B tracker
module ADSB
  module Constants
    # ===========================================
    # SDR / Radio Configuration
    # ===========================================
    FREQUENCY_HZ = 1_090_000_000           # ADS-B frequency (1090 MHz)
    SAMPLE_RATE_HZ = 2_000_000             # 2 MHz sample rate
    SAMPLES_PER_READ = 262_144             # Buffer size for SDR reads
    DEFAULT_GAIN_TENTHS_DB = 496           # Maximum gain (49.6 dB)

    # ===========================================
    # Demodulator Configuration
    # ===========================================
    SAMPLES_PER_US = 2.0                   # Samples per microsecond at 2 MHz
    PREAMBLE_SAMPLES = 16                  # 8 microseconds at 2 MHz
    LONG_MESSAGE_BITS = 112                # DF17 extended squitter
    LONG_MESSAGE_SAMPLES = 224             # 112 bits * 2 samples/bit
    SHORT_MESSAGE_BITS = 56                # DF4, DF5, DF11
    SHORT_MESSAGE_SAMPLES = 112            # 56 bits * 2 samples/bit

    # Signal detection thresholds
    MIN_SIGNAL_LEVEL = 0.008               # Minimum preamble signal level
    MIN_BIT_DELTA = 0.003                  # Minimum average bit delta (noise rejection)
    LOW_CONFIDENCE_BIT_THRESHOLD = 0.004   # Below this, copy previous bit

    # Phase correction factors
    PHASE_CORRECTION_AMPLIFY = 1.25        # Amplify next first-half after bit=1
    PHASE_CORRECTION_DAMPEN = 0.8          # Dampen next first-half after bit=0

    # Stats/debug
    DEMOD_STATS_INTERVAL_SEC = 5           # How often to log demod stats
    MAX_DF17_DEBUG_FAILURES = 5            # Max CRC failures to log for DF17

    # ===========================================
    # ADS-B Protocol Constants
    # ===========================================
    CRC24_POLY = 0x1FFF409                 # Mode S CRC-24 polynomial

    # Downlink Format types
    DF_ALTITUDE_REPLY = 4                  # Surveillance Altitude Reply (56 bits)
    DF_IDENTITY_REPLY = 5                  # Surveillance Identity Reply (56 bits)
    DF_ADSB = 17                           # ADS-B Extended Squitter (112 bits)
    DF_COMM_B_ALT = 20                     # Comm-B Altitude Reply (112 bits)
    DF_COMM_B_IDENTITY = 21                # Comm-B Identity Reply (112 bits)

    # Type codes for message types
    TC_IDENTIFICATION = (1..4).to_a
    TC_SURFACE_POSITION = (5..8).to_a
    TC_AIRBORNE_POSITION_BARO = (9..18).to_a
    TC_AIRBORNE_VELOCITY = [ 19 ]
    TC_AIRBORNE_POSITION_GNSS = (20..22).to_a

    # CPR (Compact Position Reporting) constants
    NZ = 15                                # Number of latitude zones
    D_LAT_EVEN = 360.0 / (4 * NZ)          # Latitude zone size (even)
    D_LAT_ODD = 360.0 / (4 * NZ - 1)       # Latitude zone size (odd)
    CPR_MAX = 131_072.0                    # 2^17 for CPR normalization

    # Aircraft identification character lookup
    CALLSIGN_CHARSET = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ##### ###############0123456789######"

    # Altitude decoding
    ALTITUDE_25FT_RESOLUTION = 25          # Q-bit = 1
    ALTITUDE_100FT_RESOLUTION = 100        # Q-bit = 0 (Gillham)
    ALTITUDE_OFFSET_25FT = 1000            # Subtract from 25ft altitude
    ALTITUDE_OFFSET_100FT = 1300           # Subtract from Gillham altitude
    BDS40_ALTITUDE_RESOLUTION = 16         # Selected altitude resolution

    # Velocity decoding
    VERTICAL_RATE_RESOLUTION = 64          # ft/min per LSB
    HEADING_RESOLUTION = 360.0 / 1024      # Degrees per LSB for airspeed heading
    BARO_RATE_RESOLUTION = 32              # ft/min per LSB for BDS 6,0

    # EHS (Enhanced Surveillance) decode factors
    ROLL_ANGLE_SCALE = 45.0 / 256          # Degrees per LSB
    TRACK_ANGLE_SCALE = 90.0 / 512         # Degrees per LSB
    HEADING_SCALE = 90.0 / 512             # Degrees per LSB
    TRACK_RATE_SCALE = 8.0 / 256           # Degrees/sec per LSB
    GROUND_SPEED_RESOLUTION = 2            # Knots per LSB
    TRUE_AIRSPEED_RESOLUTION = 2           # Knots per LSB
    MACH_SCALE = 0.008                     # Mach per LSB
    BARO_SETTING_OFFSET = 800              # Millibars offset
    BARO_SETTING_SCALE = 0.1               # Millibars per LSB

    # ===========================================
    # Aircraft Tracking
    # ===========================================
    AIRCRAFT_TIMEOUT_SEC = 60              # Remove aircraft after no messages
    HISTORY_SAVE_INTERVAL_SEC = 30         # How often to save to history DB
    MAX_POSITION_HISTORY = 100             # Trail points to keep in memory
    CPR_FRAME_MAX_AGE_SEC = 10             # Max age difference for even/odd CPR

    # Signal strength smoothing (exponential moving average)
    SIGNAL_STRENGTH_OLD_WEIGHT = 0.7       # Weight for previous value
    SIGNAL_STRENGTH_NEW_WEIGHT = 0.3       # Weight for new sample
    SIGNAL_STRENGTH_MAX = 0.4              # Reference max for percentage display

    # ICAO recovery
    ICAO_CANDIDATE_REFRESH_SEC = 60        # How often to refresh candidate list
    ICAO_CANDIDATE_HOURS = 2               # Look back this many hours for candidates

    # ===========================================
    # Geographic / Coverage Analysis
    # ===========================================
    EARTH_RADIUS_NM = 3440.065             # Earth radius in nautical miles
    DEGREES_TO_RADIANS = Math::PI / 180    # Conversion factor

    # Coverage analysis defaults
    DEFAULT_COVERAGE_HOURS = 168           # 7 days
    COVERAGE_DIRECTIONS = %w[N NE E SE S SW W NW].freeze
    COVERAGE_DEGREES_PER_SECTOR = 45       # 360 / 8 directions
    COVERAGE_HISTOGRAM_BUCKET_NM = 10      # Range histogram bucket size
    COVERAGE_HISTOGRAM_BUCKETS = 30        # 0-300nm in 10nm buckets

    # Altitude bands for coverage analysis (feet)
    ALTITUDE_BANDS = [
      { name: "0-10k", min: 0, max: 10_000 },
      { name: "10-20k", min: 10_000, max: 20_000 },
      { name: "20-30k", min: 20_000, max: 30_000 },
      { name: "30-40k", min: 30_000, max: 40_000 },
      { name: "40k+", min: 40_000, max: 100_000 }
    ].freeze

    # ===========================================
    # API / Web Configuration
    # ===========================================
    OPENSKY_CACHE_SEC = 300                # 5 minute cache for OpenSky API
    OPENSKY_LOOKBACK_SEC = 86_400          # 24 hours for flight lookup
    HTTP_TIMEOUT_SEC = 5                   # API request timeout
    WEBSOCKET_BROADCAST_SEC = 5            # Full aircraft list broadcast interval

    # Default API limits
    DEFAULT_HEATMAP_HOURS = 24
    DEFAULT_HEATMAP_LIMIT = 5000
    DEFAULT_HISTORY_LIMIT = 100
    DEFAULT_EXPORT_DAYS = 30

    # ===========================================
    # TUI Configuration
    # ===========================================
    TUI_REFRESH_SEC = 2                    # Screen refresh interval
    TUI_AGE_THRESHOLD_SEC = 60             # Show as minutes after this
    TUI_DEFAULT_SORT_DISTANCE = 999        # Sort aircraft without distance to end
    TUI_TERMINAL_WIDTH = 80                # Assumed terminal width
  end
end
