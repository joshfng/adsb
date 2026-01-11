# frozen_string_literal: true

class Api::ExportController < ApplicationController
  before_action :require_history

  def csv
    send_data AdsbService.receiver.history.export_csv,
              filename: "adsb-export-#{Date.today}.csv",
              type: "text/csv"
  end
end
