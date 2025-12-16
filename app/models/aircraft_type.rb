class AircraftType < ApplicationRecord
  self.primary_key = :code

  has_many :registrations, foreign_key: :mfr_mdl_code, primary_key: :code

  validates :code, presence: true, uniqueness: true
end
