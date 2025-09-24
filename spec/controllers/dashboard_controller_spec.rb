require 'rails_helper'

RSpec.describe DashboardController, type: :controller do
  describe "GET #index" do
    let(:database_type) { create(:database_type) }
    let(:provider) { create(:provider) }
    let!(:clusters) { create_list(:cluster, 3, database_type: database_type) }
    let!(:providers) { create_list(:provider, 2, provider_type: provider.provider_type) }
    let!(:nodes) { create_list(:node, 4, cluster: clusters.first, provider: provider, database_type_version: create(:database_type_version, database_type: database_type)) }

    it "returns a success response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns counts" do
      get :index
      expect(assigns(:clusters_count)).to eq(3)
      expect(assigns(:providers_count)).to eq(3) # 2 created + 1 from let
      expect(assigns(:nodes_count)).to eq(4)
    end

    it "assigns recent clusters" do
      get :index
      expect(assigns(:recent_clusters)).to match_array(clusters)
    end

    it "assigns recent providers" do
      get :index
      expect(assigns(:recent_providers).count).to eq(3)
    end

    it "limits recent clusters to 5" do
      create_list(:cluster, 10, database_type: database_type)
      get :index
      expect(assigns(:recent_clusters).count).to eq(5)
    end

    it "limits recent providers to 5" do
      create_list(:provider, 10, provider_type: provider.provider_type)
      get :index
      expect(assigns(:recent_providers).count).to eq(5)
    end

    it "orders recent clusters by created_at desc" do
      get :index
      recent_clusters = assigns(:recent_clusters)
      expect(recent_clusters.first.created_at).to be >= recent_clusters.last.created_at
    end

    it "orders recent providers by created_at desc" do
      get :index
      recent_providers = assigns(:recent_providers)
      expect(recent_providers.first.created_at).to be >= recent_providers.last.created_at
    end
  end
end
