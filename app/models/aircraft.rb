# frozen_string_literal: true

class Aircraft < ApplicationRecord
  self.primary_key = :icao
  self.table_name = "aircraft"

  has_many :sightings, foreign_key: :icao, primary_key: :icao
  has_one :registration, foreign_key: :icao_hex, primary_key: :icao

  # Validations
  validates :icao, presence: true, uniqueness: true, format: { with: /\A[0-9A-Fa-f]{6}\z/, message: "must be 6-character hex" }
  validates :sighting_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :callsign, length: { maximum: 8 }, allow_nil: true

  # Scopes
  scope :recent, -> { order(last_seen: :desc) }
  scope :seen_within, ->(hours) { where("last_seen > ?", hours.hours.ago) }
  scope :most_seen, ->(limit = 10) { order(sighting_count: :desc).limit(limit) }
  scope :with_callsign, -> { where.not(callsign: nil) }
end
