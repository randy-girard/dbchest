class DashboardController < ApplicationController
  def index
    @clusters_count = Cluster.count
    @providers_count = Provider.count
    @nodes_count = Node.count
    @recent_clusters = Cluster.order(created_at: :desc).limit(5)
    @recent_providers = Provider.order(created_at: :desc).limit(5)
  end
end
