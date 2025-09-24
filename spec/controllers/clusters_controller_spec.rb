require 'rails_helper'

RSpec.describe ClustersController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:valid_attributes) { { name: "Test Cluster", database_type_id: database_type.id } }
  let(:invalid_attributes) { { name: "", database_type_id: nil } }

  describe "GET #index" do
    it "returns a success response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns @clusters" do
      cluster # create the cluster
      get :index
      expect(assigns(:clusters)).to include(cluster)
    end

    context "with multiple clusters" do
      let!(:clusters) { create_list(:cluster, 3, database_type: database_type) }

      it "assigns all clusters" do
        get :index
        expect(assigns(:clusters)).to match_array(clusters)
      end
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      get :show, params: { id: cluster.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested cluster" do
      get :show, params: { id: cluster.to_param }
      expect(assigns(:cluster)).to eq(cluster)
    end

    context "with non-existent cluster" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "GET #new" do
    it "returns a success response" do
      get :new
      expect(response).to be_successful
    end

    it "assigns a new cluster" do
      get :new
      expect(assigns(:cluster)).to be_a_new(Cluster)
    end

    it "assigns database types with versions" do
      database_type_with_version = create(:database_type)
      create(:database_type_version, database_type: database_type_with_version)

      get :new
      expect(assigns(:database_types)).to include(database_type_with_version)
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      get :edit, params: { id: cluster.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested cluster" do
      get :edit, params: { id: cluster.to_param }
      expect(assigns(:cluster)).to eq(cluster)
    end

    it "assigns database types with versions" do
      database_type_with_version = create(:database_type)
      create(:database_type_version, database_type: database_type_with_version)

      get :edit, params: { id: cluster.to_param }
      expect(assigns(:database_types)).to include(database_type_with_version)
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

      it "assigns the cluster" do
        post :create, params: { cluster: valid_attributes }
        expect(assigns(:cluster)).to be_persisted
      end
    end

    context "with invalid params" do
      it "does not create a new Cluster" do
        expect {
          post :create, params: { cluster: invalid_attributes }
        }.not_to change(Cluster, :count)
      end

      it "renders the new template" do
        post :create, params: { cluster: invalid_attributes }
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "assigns database types" do
        database_type_with_version = create(:database_type)
        create(:database_type_version, database_type: database_type_with_version)

        post :create, params: { cluster: invalid_attributes }
        expect(assigns(:database_types)).to include(database_type_with_version)
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

      it "assigns the cluster" do
        put :update, params: { id: cluster.to_param, cluster: new_attributes }
        expect(assigns(:cluster)).to eq(cluster)
      end
    end

    context "with invalid params" do
      it "does not update the cluster" do
        original_name = cluster.name
        put :update, params: { id: cluster.to_param, cluster: invalid_attributes }
        cluster.reload
        expect(cluster.name).to eq(original_name)
      end

      it "renders the edit template" do
        put :update, params: { id: cluster.to_param, cluster: invalid_attributes }
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "assigns database types" do
        database_type_with_version = create(:database_type)
        create(:database_type_version, database_type: database_type_with_version)

        put :update, params: { id: cluster.to_param, cluster: invalid_attributes }
        expect(assigns(:database_types)).to include(database_type_with_version)
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
