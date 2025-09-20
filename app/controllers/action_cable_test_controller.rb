class ActionCableTestController < ApplicationController
  def index
    @node = Node.first
    
    if @node.nil?
      redirect_to root_path, alert: "No nodes found. Please create a node first to test ActionCable."
      return
    end
  end

  def broadcast_test
    @node = Node.find(params[:id])
    
    # Simulate a status update
    messages = [
      "Testing ActionCable broadcast...",
      "This is a test message",
      "Broadcasting to all streams",
      "Check your browser console!"
    ]
    
    message = messages.sample
    @node.update_status!('active', message)
    
    render json: { 
      success: true, 
      message: "Broadcast sent: #{message}",
      node_id: @node.id,
      status: @node.status
    }
  end
end
