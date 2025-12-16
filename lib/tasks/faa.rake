# frozen_string_literal: true

require "net/http"
require "uri"
require "zip"
require "fileutils"

namespace :faa do
  DATA_DIR = Rails.root.join("db", "seeds", "faa")
  FAA_DOWNLOAD_URL = "https://registry.faa.gov/database/ReleasableAircraft.zip"

  desc "Download FAA aircraft registry data"
  task download: :environment do
    puts "=== Downloading FAA Aircraft Registry ==="
    FileUtils.mkdir_p(DATA_DIR)

    zip_path = DATA_DIR.join("ReleasableAircraft.zip")

    puts "  Downloading from FAA (this may take a few minutes)..."
    download_file(FAA_DOWNLOAD_URL, zip_path)

    puts "  Extracting archive..."
    extract_zip(zip_path, DATA_DIR)

    puts "  Cleaning up..."
    File.delete(zip_path) if File.exist?(zip_path)

    puts "  Download complete! Files saved to #{DATA_DIR}"
  end

  desc "Seed FAA aircraft database from MASTER.txt and ACFTREF.txt"
  task seed: :environment do
    puts "=== FAA Aircraft Database ==="

    unless data_files_exist?
      puts "  FAA data files not found in #{DATA_DIR}"
      puts "  Run: bin/rails faa:download"
      puts "  Or download from: https://www.faa.gov/licenses_certificates/aircraft_certification/aircraft_registry/releasable_aircraft_download"
      exit 1
    end

    import_aircraft_types
    import_registrations

    puts "  FAA seed complete!"
  end

  desc "Download and seed FAA data"
  task setup: [ :download, :seed ]

  desc "Reset and reseed FAA data"
  task reseed: :environment do
    puts "Deleting existing FAA data..."
    Registration.delete_all
    AircraftType.delete_all
    Rake::Task["faa:seed"].invoke
  end

  desc "Show FAA data statistics"
  task stats: :environment do
    puts "=== FAA Database Statistics ==="
    puts "  Aircraft Types: #{AircraftType.count}"
    puts "  Registrations: #{Registration.count}"
  end

  def data_files_exist?
    File.exist?(DATA_DIR.join("ACFTREF.txt")) &&
      File.exist?(DATA_DIR.join("MASTER.txt"))
  end

  def import_aircraft_types
    path = DATA_DIR.join("ACFTREF.txt")
    puts "  Importing aircraft types..."

    AircraftType.delete_all

    count = 0
    batch = []
    batch_size = 1000

    File.foreach(path).with_index do |line, idx|
      next if idx == 0 # Skip header

      parts = line.encode("UTF-8", invalid: :replace, undef: :replace).split(",")
      code = parts[0]&.strip
      next if code.nil? || code.empty?

      batch << {
        code: code,
        manufacturer: parts[1]&.strip,
        model: parts[2]&.strip,
        aircraft_type: parse_aircraft_type(parts[3]&.strip),
        engine_type: parse_engine_type(parts[4]&.strip),
        num_engines: parts[7]&.strip&.to_i,
        num_seats: parts[8]&.strip&.to_i,
        weight_class: parts[9]&.strip,
        speed: parts[10]&.strip&.to_i
      }

      count += 1

      if batch.size >= batch_size
        AircraftType.insert_all(batch)
        batch = []
        print "\r    #{count} aircraft types..."
      end
    end

    # Insert remaining records
    AircraftType.insert_all(batch) unless batch.empty?
    puts "\r    #{count} aircraft types imported"
  end

  def import_registrations
    path = DATA_DIR.join("MASTER.txt")
    puts "  Importing registrations..."

    Registration.delete_all

    count = 0
    batch = []
    batch_size = 10000

    File.foreach(path).with_index do |line, idx|
      next if idx == 0 # Skip header

      parts = line.encode("UTF-8", invalid: :replace, undef: :replace).split(",")
      icao_hex = parts[33]&.strip&.upcase # MODE S CODE HEX
      next if icao_hex.nil? || icao_hex.empty?

      year = parts[4]&.strip
      year = year.to_i if year && !year.empty?
      year = nil if year == 0

      batch << {
        icao_hex: icao_hex,
        n_number: "N#{parts[0]&.strip}",
        serial_number: parts[1]&.strip,
        mfr_mdl_code: parts[2]&.strip,
        year: year,
        owner: parts[6]&.strip,
        city: parts[9]&.strip,
        state: parts[10]&.strip,
        aircraft_type_code: parts[18]&.strip,
        engine_type_code: parts[19]&.strip
      }

      count += 1

      if batch.size >= batch_size
        Registration.insert_all(batch)
        batch = []
        print "\r    #{count} registrations..."
      end
    end

    # Insert remaining records
    Registration.insert_all(batch) unless batch.empty?
    puts "\r    #{count} registrations imported"
  end

  def download_file(url, destination)
    uri = URI.parse(url)

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      request = Net::HTTP::Get.new(uri)

      http.request(request) do |response|
        case response
        when Net::HTTPSuccess
          File.open(destination, "wb") do |file|
            response.read_body do |chunk|
              file.write(chunk)
              print "."
            end
          end
          puts " done!"
        when Net::HTTPRedirection
          download_file(response["location"], destination)
        else
          raise "Download failed: #{response.code} #{response.message}"
        end
      end
    end
  end

  def extract_zip(zip_path, destination)
    Zip::File.open(zip_path) do |zip_file|
      zip_file.each do |entry|
        entry_path = File.join(destination, entry.name)
        FileUtils.mkdir_p(File.dirname(entry_path))
        zip_file.extract(entry, entry_path) { true } # Overwrite existing
        puts "    Extracted: #{entry.name}"
      end
    end
  end

  def parse_aircraft_type(code)
    case code&.to_s&.strip
    when "1" then "Glider"
    when "2" then "Balloon"
    when "3" then "Blimp/Dirigible"
    when "4" then "Fixed Wing Single Engine"
    when "5" then "Fixed Wing Multi Engine"
    when "6" then "Rotorcraft"
    when "7" then "Weight-Shift-Control"
    when "8" then "Powered Parachute"
    when "9" then "Gyroplane"
    else "Unknown"
    end
  end

  def parse_engine_type(code)
    case code&.to_s&.strip
    when "0" then "None"
    when "1" then "Reciprocating"
    when "2" then "Turbo-prop"
    when "3" then "Turbo-shaft"
    when "4" then "Turbo-jet"
    when "5" then "Turbo-fan"
    when "6" then "Ramjet"
    when "7" then "2 Cycle"
    when "8" then "4 Cycle"
    when "9" then "Unknown"
    when "10" then "Electric"
    when "11" then "Rotary"
    else "Unknown"
    end
  end
end
