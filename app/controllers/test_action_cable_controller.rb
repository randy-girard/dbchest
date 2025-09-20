class TestActionCableController < ApplicationController
  # POST /test_actioncable/:node_id/update_status
  def update_status
    @node = Node.find(params[:node_id])
    status = params[:status] || 'provisioning'
    message = params[:message] || "Test update from web interface"
    
    Rails.logger.info "🧪 Web test: Updating node #{@node.id} to status '#{status}'"
    
    begin
      @node.update_status!(status, message)
      
      respond_to do |format|
        format.json { 
          render json: { 
            success: true, 
            node_id: @node.id,
            status: @node.status,
            message: "Status updated to '#{status}' with ActionCable broadcast"
          }
        }
        format.html { 
          redirect_back_or_to cluster_path(@node.cluster), 
                           notice: "✅ Test: Updated #{@node.name} to '#{status}'"
        }
      end
    rescue => e
      respond_to do |format|
        format.json { render json: { success: false, error: e.message } }
        format.html { 
          redirect_back_or_to cluster_path(@node.cluster), 
                           alert: "❌ Error: #{e.message}"
        }
      end
    end
  end
  
  # GET /test_actioncable/:node_id
  def show
    @node = Node.find(params[:node_id])
    @test_statuses = [
      { status: 'pending', message: 'Test: Node is pending' },
      { status: 'provisioning', message: 'Test: Provisioning resources...' },
      { status: 'configuring', message: 'Test: Configuring settings...' },
      { status: 'active', message: 'Test: Node is now active' },
      { status: 'destroying', message: 'Test: Destroying node...' }
    ]
  end
end
