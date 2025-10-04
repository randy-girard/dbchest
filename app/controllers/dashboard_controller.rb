class DashboardController < ApplicationController
  def index
    @clusters_count = Cluster.count
    @providers_count = Provider.count
    @nodes_count = Node.count
    @recent_clusters = Cluster.recent.limit(5)
    @recent_providers = Provider.recent.limit(5)
  end
end
