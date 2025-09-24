require 'rails_helper'

RSpec.describe ClustersController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:cluster) { create(:cluster) }
  let(:valid_attributes) { { name: "Test Cluster", database_type_id: database_type.id } }

  describe "GET #index" do
    it "returns a success response" do
      get :index
      expect(response).to be_successful
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      get :show, params: { id: cluster.to_param }
      expect(response).to be_successful
    end
  end

  describe "GET #new" do
    it "returns a success response" do
      get :new
      expect(response).to be_successful
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      get :edit, params: { id: cluster.to_param }
      expect(response).to be_successful
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Cluster" do
        expect {
          post :create, params: { cluster: valid_attributes }
        }.to change(Cluster, :count).by(1)
      end

      it "redirects to the created cluster" do
        post :create, params: { cluster: valid_attributes }
        expect(response).to redirect_to(Cluster.last)
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) { { name: "Updated Cluster" } }

      it "updates the requested cluster" do
        put :update, params: { id: cluster.to_param, cluster: new_attributes }
        cluster.reload
        expect(cluster.name).to eq("Updated Cluster")
      end

      it "redirects to the cluster" do
        put :update, params: { id: cluster.to_param, cluster: valid_attributes }
        expect(response).to redirect_to(cluster)
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested cluster" do
      cluster # create the cluster
      expect {
        delete :destroy, params: { id: cluster.to_param }
      }.to change(Cluster, :count).by(-1)
    end

    it "redirects to the clusters list" do
      delete :destroy, params: { id: cluster.to_param }
      expect(response).to redirect_to(clusters_url)
    end
  end
end
