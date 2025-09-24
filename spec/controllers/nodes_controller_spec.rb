require 'rails_helper'

RSpec.describe NodesController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  
  let(:valid_attributes) do
    {
      name: "Test Node",
      provider_id: provider.id,
      database_type_version_id: database_type_version.id
    }
  end
  
  let(:invalid_attributes) do
    {
      name: "",
      provider_id: provider.id,
      database_type_version_id: database_type_version.id
    }
  end

  before do
    # Mock the provision! method to avoid actual provisioning
    allow_any_instance_of(Node).to receive(:provision!)
    allow_any_instance_of(Node).to receive(:provision_replica!)
    allow_any_instance_of(Node).to receive(:deprovision!) do |instance|
      instance.destroy!
    end
  end

  describe "GET #index" do
    it "returns a success response" do
      get :index, params: { cluster_id: cluster.to_param }
      expect(response).to be_successful
    end

    it "assigns @cluster" do
      get :index, params: { cluster_id: cluster.to_param }
      expect(assigns(:cluster)).to eq(cluster)
    end

    it "assigns @nodes" do
      node # create the node
      get :index, params: { cluster_id: cluster.to_param }
      expect(assigns(:nodes)).to include(node)
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      get :show, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested node" do
      get :show, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(assigns(:node)).to eq(node)
    end

    it "assigns the cluster" do
      get :show, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(assigns(:cluster)).to eq(cluster)
    end

    context "when node is being destroyed" do
      before { node.update!(status: 'destroying') }

      it "redirects to cluster with alert" do
        get :show, params: { cluster_id: cluster.to_param, id: node.to_param }
        expect(response).to redirect_to(cluster)
        expect(flash[:alert]).to include("being destroyed")
      end
    end
  end

  describe "GET #new" do
    it "returns a success response" do
      get :new, params: { cluster_id: cluster.to_param }
      expect(response).to be_successful
    end

    it "assigns a new node" do
      get :new, params: { cluster_id: cluster.to_param }
      expect(assigns(:node)).to be_a_new(Node)
      expect(assigns(:node).cluster).to eq(cluster)
    end

    it "assigns providers" do
      get :new, params: { cluster_id: cluster.to_param }
      expect(assigns(:providers)).to include(provider)
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      get :edit, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested node" do
      get :edit, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(assigns(:node)).to eq(node)
    end

    it "assigns providers" do
      get :edit, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(assigns(:providers)).to include(provider)
    end

    context "when node is being destroyed" do
      before { node.update!(status: 'destroying') }

      it "redirects with alert" do
        get :edit, params: { cluster_id: cluster.to_param, id: node.to_param }
        expect(response).to redirect_to(cluster)
        expect(flash[:alert]).to include("being destroyed")
      end
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Node" do
        expect {
          post :create, params: { cluster_id: cluster.to_param, node: valid_attributes }
        }.to change(Node, :count).by(1)
      end

      it "assigns the node to the cluster" do
        post :create, params: { cluster_id: cluster.to_param, node: valid_attributes }
        expect(assigns(:node).cluster).to eq(cluster)
      end

      it "calls provision! on the node" do
        expect_any_instance_of(Node).to receive(:provision!)
        post :create, params: { cluster_id: cluster.to_param, node: valid_attributes }
      end

      it "redirects to the created node" do
        post :create, params: { cluster_id: cluster.to_param, node: valid_attributes }
        expect(response).to redirect_to([cluster, Node.last])
      end

      it "sets a success notice" do
        post :create, params: { cluster_id: cluster.to_param, node: valid_attributes }
        expect(flash[:notice]).to include("successfully created and is being provisioned")
      end
    end

    context "with invalid params" do
      it "does not create a new Node" do
        expect {
          post :create, params: { cluster_id: cluster.to_param, node: invalid_attributes }
        }.not_to change(Node, :count)
      end

      it "renders the new template" do
        post :create, params: { cluster_id: cluster.to_param, node: invalid_attributes }
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "builds node settings for form repopulation" do
        allow_any_instance_of(Node).to receive(:node_settings).and_return([])
        expect_any_instance_of(Node).to receive(:build_node_settings!)
        post :create, params: { cluster_id: cluster.to_param, node: invalid_attributes }
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) { { name: "Updated Node" } }

      it "updates the requested node" do
        put :update, params: { cluster_id: cluster.to_param, id: node.to_param, node: new_attributes }
        node.reload
        expect(node.name).to eq("Updated Node")
      end

      it "redirects to the node" do
        put :update, params: { cluster_id: cluster.to_param, id: node.to_param, node: new_attributes }
        expect(response).to redirect_to([cluster, node])
      end

      it "sets a success notice" do
        put :update, params: { cluster_id: cluster.to_param, id: node.to_param, node: new_attributes }
        expect(flash[:notice]).to eq("Node was successfully updated.")
      end
    end

    context "with invalid params" do
      it "does not update the node" do
        original_name = node.name
        put :update, params: { cluster_id: cluster.to_param, id: node.to_param, node: invalid_attributes }
        node.reload
        expect(node.name).to eq(original_name)
      end

      it "renders the edit template" do
        put :update, params: { cluster_id: cluster.to_param, id: node.to_param, node: invalid_attributes }
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when node is being destroyed" do
      before { node.update!(status: 'destroying') }

      it "redirects with alert" do
        put :update, params: { cluster_id: cluster.to_param, id: node.to_param, node: { name: "New Name" } }
        expect(response).to redirect_to(cluster)
        expect(flash[:alert]).to include("being destroyed")
      end
    end
  end

  describe "GET #confirm_destroy" do
    it "returns a success response" do
      get :confirm_destroy, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(response).to be_successful
    end

    it "assigns the node" do
      get :confirm_destroy, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(assigns(:node)).to eq(node)
    end

    it "assigns replicas" do
      replica = create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: node)
      get :confirm_destroy, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(assigns(:replicas)).to include(replica)
    end
  end

  describe "GET #add_replica" do
    it "redirects with alert when node cannot create replicas" do
      get :add_replica, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(response).to redirect_to([cluster, node])
      expect(flash[:alert]).to include("Cannot create replica")
    end

    it "assigns the node" do
      get :add_replica, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(assigns(:node)).to eq(node)
    end

    it "assigns providers" do
      get :add_replica, params: { cluster_id: cluster.to_param, id: node.to_param }
      expect(assigns(:providers)).to include(provider)
    end

    context "when node cannot create replicas" do
      before { allow(node).to receive(:can_create_replicas?).and_return(false) }

      it "redirects with alert" do
        get :add_replica, params: { cluster_id: cluster.to_param, id: node.to_param }
        expect(response).to redirect_to([cluster, node])
        expect(flash[:alert]).to include("Cannot create replica")
      end
    end
  end

  describe "GET #config_partial" do
    it "returns a success response" do
      get :config_partial, params: { cluster_id: cluster.to_param, provider_id: provider.id }
      expect(response).to be_successful
    end

    it "assigns the provider" do
      get :config_partial, params: { cluster_id: cluster.to_param, provider_id: provider.id }
      expect(assigns(:provider)).to eq(provider)
    end

    it "assigns a new node" do
      get :config_partial, params: { cluster_id: cluster.to_param, provider_id: provider.id }
      expect(assigns(:node)).to be_a_new(Node)
    end

    it "builds node settings" do
      option = create(:provider_type_node_option, provider_type: provider.provider_type)
      get :config_partial, params: { cluster_id: cluster.to_param, provider_id: provider.id }
      expect(assigns(:node).node_settings).not_to be_empty
    end
  end

  describe "POST #create_replica" do
    let(:replica_attributes) do
      {
        name: "Replica Node",
        provider_id: provider.id
      }
    end

    before do
      node.update!(status: 'active') # Node must be active to create replicas
    end



    context "with valid params" do
      it "creates a new replica node" do
        expect {
          post :create_replica, params: { cluster_id: cluster.to_param, id: node.to_param, node: replica_attributes }
        }.to change(Node, :count).by(1)
      end

      it "sets the parent node" do
        post :create_replica, params: { cluster_id: cluster.to_param, id: node.to_param, node: replica_attributes }
        replica = Node.last
        expect(replica.parent_node).to eq(node)
      end

      it "calls provision_replica!" do
        expect_any_instance_of(Node).to receive(:provision_replica!)
        post :create_replica, params: { cluster_id: cluster.to_param, id: node.to_param, node: replica_attributes }
      end

      it "redirects to the parent node" do
        post :create_replica, params: { cluster_id: cluster.to_param, id: node.to_param, node: replica_attributes }
        expect(response).to redirect_to([cluster, node])
      end
    end

    context "with invalid params" do
      let(:invalid_replica_attributes) { { name: "", provider_id: provider.id } }

      it "does not create a new node" do
        expect {
          post :create_replica, params: { cluster_id: cluster.to_param, id: node.to_param, node: invalid_replica_attributes }
        }.not_to change(Node, :count)
      end

      it "renders the add_replica template" do
        post :create_replica, params: { cluster_id: cluster.to_param, id: node.to_param, node: invalid_replica_attributes }
        expect(response).to render_template(:add_replica)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE #destroy" do
    before do
      allow_any_instance_of(Node).to receive(:deprovision!) { |instance| instance.destroy! }
    end

    context "when node has no replicas" do
      it "destroys the requested node" do
        node_id = node.id
        delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param }
        expect(Node.find_by(id: node_id)).to be_nil
      end

      it "calls deprovision!" do
        expect_any_instance_of(Node).to receive(:deprovision!)
        delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param }
      end

      it "redirects to the cluster" do
        delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param }
        expect(response).to redirect_to(cluster)
      end
    end

    context "when node has replicas" do
      let!(:replica) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: node) }

      context "without replica_action parameter" do
        it "redirects to confirm_destroy" do
          delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param }
          expect(response).to redirect_to(confirm_destroy_cluster_node_path(cluster, node))
          expect(flash[:alert]).to include("has replicas")
        end
      end

      context "with delete_all replica_action" do
        it "destroys all replicas" do
          # The global mock already handles deprovision! calls
          delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param, replica_action: 'delete_all' }
          # Verify that both the primary node and replicas are destroyed
          expect(Node.find_by(id: node.id)).to be_nil
          expect(Node.find_by(id: replica.id)).to be_nil
        end

        it "destroys the primary node" do
          node_id = node.id
          delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param, replica_action: 'delete_all' }
          expect(Node.find_by(id: node_id)).to be_nil
        end

        it "sets appropriate notice" do
          delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param, replica_action: 'delete_all' }
          expect(flash[:notice]).to include("replica(s) are being removed")
        end
      end

      context "with promote_first replica_action" do
        it "promotes first replica to primary" do
          delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param, replica_action: 'promote_first' }
          replica.reload
          expect(replica.parent_node).to be_nil
        end

        it "destroys the original primary" do
          node_id = node.id
          delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param, replica_action: 'promote_first' }
          expect(Node.find_by(id: node_id)).to be_nil
        end

        it "sets appropriate notice" do
          delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param, replica_action: 'promote_first' }
          expect(flash[:notice]).to include("promoted to primary")
        end
      end
    end
  end

  # JSON format tests
  describe "JSON responses" do
    describe "POST #create" do
      context "with valid params" do
        it "returns JSON with created status" do
          post :create, params: { cluster_id: cluster.to_param, node: valid_attributes }, format: :json
          expect(response).to have_http_status(:created)
          expect(response.content_type).to include('application/json')
        end
      end

      context "with invalid params" do
        it "returns JSON with errors" do
          post :create, params: { cluster_id: cluster.to_param, node: invalid_attributes }, format: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.content_type).to include('application/json')
        end
      end
    end

    describe "PUT #update" do
      context "with valid params" do
        it "returns JSON with ok status" do
          put :update, params: { cluster_id: cluster.to_param, id: node.to_param, node: { name: "Updated" } }, format: :json
          expect(response).to have_http_status(:ok)
          expect(response.content_type).to include('application/json')
        end
      end

      context "with invalid params" do
        it "returns JSON with errors" do
          put :update, params: { cluster_id: cluster.to_param, id: node.to_param, node: invalid_attributes }, format: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.content_type).to include('application/json')
        end
      end
    end

    describe "DELETE #destroy" do
      it "returns no content status" do
        delete :destroy, params: { cluster_id: cluster.to_param, id: node.to_param }, format: :json
        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
