# frozen_string_literal: true

require "rails_helper"

RSpec.describe FAALookup do
  let(:lookup) { FAALookup.new }

  before do
    # Clean up test data
    Registration.delete_all
    AircraftType.delete_all
  end

  describe "#initialize" do
    it "creates instance without error" do
      expect(FAALookup.new).to be_a(FAALookup)
    end
  end

  describe "#lookup" do
    context "with no data" do
      it "returns nil for unknown ICAO" do
        result = lookup.lookup("ABCDEF")
        expect(result).to be_nil
      end
    end

    context "with registration data" do
      before do
        # Create aircraft type first (primary key is 'code')
        AircraftType.create!(
          code: "2072001",
          manufacturer: "BOEING",
          model: "737-800",
          aircraft_type: "Fixed Wing Multi-Engine",
          engine_type: "Turbo-Jet",
          num_engines: 2,
          num_seats: 189,
          weight_class: "OVER 12,500 LBS"
        )

        # Create registration (mfr_mdl_code references aircraft_types.code)
        Registration.create!(
          icao_hex: "A12345",
          n_number: "N12345",
          serial_number: "12345",
          mfr_mdl_code: "2072001",
          year: 2015,
          owner: "UNITED AIRLINES INC",
          city: "CHICAGO",
          state: "IL",
          aircraft_type_code: "5",
          engine_type_code: "1"
        )
      end

      it "returns registration data" do
        result = lookup.lookup("A12345")

        expect(result).not_to be_nil
        expect(result[:n_number]).to eq("N12345")
        expect(result[:owner]).to eq("UNITED AIRLINES INC")
        expect(result[:city]).to eq("CHICAGO")
        expect(result[:state]).to eq("IL")
      end

      it "includes aircraft type data" do
        result = lookup.lookup("A12345")

        expect(result[:manufacturer]).to eq("BOEING")
        expect(result[:model]).to eq("737-800")
        expect(result[:num_engines]).to eq(2)
        expect(result[:num_seats]).to eq(189)
      end

      it "normalizes ICAO input" do
        # Lowercase
        expect(lookup.lookup("a12345")).not_to be_nil

        # With whitespace
        expect(lookup.lookup("  A12345  ")).not_to be_nil
      end

      it "returns nil for empty ICAO" do
        expect(lookup.lookup("")).to be_nil
        expect(lookup.lookup(nil)).to be_nil
        expect(lookup.lookup("   ")).to be_nil
      end
    end

    context "with registration but no aircraft type" do
      before do
        Registration.create!(
          icao_hex: "B67890",
          n_number: "N67890",
          mfr_mdl_code: "UNKNOWN"
        )
      end

      it "returns registration with nil type fields" do
        result = lookup.lookup("B67890")

        expect(result).not_to be_nil
        expect(result[:n_number]).to eq("N67890")
        expect(result[:manufacturer]).to be_nil
        expect(result[:model]).to be_nil
      end
    end
  end

  describe "#close" do
    it "is a no-op" do
      expect { lookup.close }.not_to raise_error
    end
  end

  describe "#count_registrations" do
    it "returns 0 with no data" do
      expect(lookup.count_registrations).to eq(0)
    end

    it "returns correct count" do
      Registration.create!(icao_hex: "C11111", n_number: "N11111")
      Registration.create!(icao_hex: "C22222", n_number: "N22222")

      expect(lookup.count_registrations).to eq(2)
    end
  end
end
