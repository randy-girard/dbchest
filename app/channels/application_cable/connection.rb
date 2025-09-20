module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # For now, we'll use a simple connection without authentication
    # In production, you might want to authenticate users here
    
    def connect
      # You can add user identification logic here if needed
      logger.add_tags "ActionCable"
    end
  end
end
