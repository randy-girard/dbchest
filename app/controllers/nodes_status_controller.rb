class NodesStatusController < ApplicationController
  # GET /clusters/:cluster_id/nodes/status
  def index
    @cluster = Cluster.find(params[:cluster_id])
    @nodes = @cluster.nodes.select(:id, :name, :status, :updated_at)
    
    respond_to do |format|
      format.json do
        render json: @nodes.map { |node|
          {
            id: node.id,
            name: node.name,
            status: node.status,
            status_display: node.status_display,
            status_badge_class: node.status_badge_class,
            updated_at: node.updated_at.iso8601
          }
        }
      end
    end
  end

  # GET /nodes/:id/status
  def show
    @node = Node.find(params[:id])
    
    respond_to do |format|
      format.json do
        render json: {
          id: @node.id,
          name: @node.name,
          status: @node.status,
          status_display: @node.status_display,
          status_badge_class: @node.status_badge_class,
          updated_at: @node.updated_at.iso8601
        }
      end
    end
  end
end
