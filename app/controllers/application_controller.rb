# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def normalize_icao(value = params[:icao])
    value.to_s.upcase.strip
  end

  def require_history
    return if AdsbService.receiver&.history
    render json: { error: "History not available" }, status: :service_unavailable
  end
end
