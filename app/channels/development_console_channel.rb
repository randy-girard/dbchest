class DevelopmentConsoleChannel < ApplicationCable::Channel
  def subscribed
    if Rails.env.development?
      stream_from "development_console"
      Rails.logger.info "DevelopmentConsoleChannel: Client subscribed to development console"
    else
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "DevelopmentConsoleChannel: Client unsubscribed from development console"
  end
end
