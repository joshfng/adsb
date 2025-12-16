class Api::ExportController < ApplicationController
  def csv
    if AdsbService.receiver&.history
      send_data AdsbService.receiver.history.export_csv,
                filename: "adsb-export-#{Date.today}.csv",
                type: "text/csv"
    else
      render plain: "Error: History not available\n"
    end
  end
end
