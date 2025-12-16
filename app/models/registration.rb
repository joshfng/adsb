class Registration < ApplicationRecord
  self.primary_key = :icao_hex

  belongs_to :aircraft_type, foreign_key: :mfr_mdl_code, primary_key: :code, optional: true
  has_one :aircraft, foreign_key: :icao, primary_key: :icao_hex

  validates :icao_hex, presence: true, uniqueness: true
end
