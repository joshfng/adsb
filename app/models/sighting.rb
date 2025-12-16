# frozen_string_literal: true

class Sighting < ApplicationRecord
  belongs_to :aircraft, foreign_key: :icao, primary_key: :icao, optional: true

  # Validations
  validates :icao, presence: true, format: { with: /\A[0-9A-Fa-f]{6}\z/, message: "must be 6-character hex" }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :altitude, numericality: { only_integer: true, greater_than_or_equal_to: -1000, less_than_or_equal_to: 100000 }, allow_nil: true
  validates :speed, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 3000 }, allow_nil: true
  validates :heading, numericality: { greater_than_or_equal_to: 0, less_than: 360 }, allow_nil: true
  validates :signal_strength, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :latitude_and_longitude_must_both_exist_or_both_be_nil

  # Scopes
  scope :recent, -> { order(seen_at: :desc) }
  scope :with_position, -> { where.not(latitude: nil, longitude: nil) }
  scope :within_hours, ->(hours) { where("seen_at > ?", hours.hours.ago) }
  scope :today, -> { where("seen_at > ?", Time.current.beginning_of_day) }
  scope :for_icao, ->(icao) { where(icao: icao.upcase) }

  private

  def latitude_and_longitude_must_both_exist_or_both_be_nil
    if latitude.present? != longitude.present?
      errors.add(:base, "latitude and longitude must both be present or both be nil")
    end
  end
end
