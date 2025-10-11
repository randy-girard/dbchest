require 'rails_helper'

RSpec.describe CredentialsController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:credential) { create(:credential, node: node) }

  let(:valid_attributes) do
    {
      username: "testuser"
    }
  end

  let(:invalid_attributes) do
    {
      username: ""
    }
  end

  describe "GET #index" do
    it "returns a success response" do
      get :index, params: { cluster_id: cluster.to_param, node_id: node.to_param }
      expect(response).to be_successful
    end

    it "assigns @cluster" do
      get :index, params: { cluster_id: cluster.to_param, node_id: node.to_param }
      expect(assigns(:cluster)).to eq(cluster)
    end

    it "assigns @node" do
      get :index, params: { cluster_id: cluster.to_param, node_id: node.to_param }
      expect(assigns(:node)).to eq(node)
    end

    it "assigns @credentials" do
      credential # create the credential
      get :index, params: { cluster_id: cluster.to_param, node_id: node.to_param }
      expect(assigns(:credentials)).to include(credential)
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      get :show, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested credential" do
      get :show, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
      expect(assigns(:credential)).to eq(credential)
    end

    it "assigns cluster and node" do
      get :show, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
      expect(assigns(:cluster)).to eq(cluster)
      expect(assigns(:node)).to eq(node)
    end
  end

  describe "GET #new" do
    it "returns a success response" do
      get :new, params: { cluster_id: cluster.to_param, node_id: node.to_param }
      expect(response).to be_successful
    end

    it "assigns a new credential" do
      get :new, params: { cluster_id: cluster.to_param, node_id: node.to_param }
      expect(assigns(:credential)).to be_a_new(Credential)
      expect(assigns(:credential).node).to eq(node)
    end

    it "assigns cluster and node" do
      get :new, params: { cluster_id: cluster.to_param, node_id: node.to_param }
      expect(assigns(:cluster)).to eq(cluster)
      expect(assigns(:node)).to eq(node)
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      get :edit, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested credential" do
      get :edit, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
      expect(assigns(:credential)).to eq(credential)
    end

    it "assigns cluster and node" do
      get :edit, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
      expect(assigns(:cluster)).to eq(cluster)
      expect(assigns(:node)).to eq(node)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      before do
        allow_any_instance_of(Credential).to receive(:provision!)
      end

      it "creates a new Credential" do
        expect {
          post :create, params: { cluster_id: cluster.to_param, node_id: node.to_param, credential: valid_attributes }
        }.to change(Credential, :count).by(1)
      end

      it "assigns the credential to the node" do
        post :create, params: { cluster_id: cluster.to_param, node_id: node.to_param, credential: valid_attributes }
        expect(assigns(:credential).node).to eq(node)
      end

      it "redirects to the cluster" do
        post :create, params: { cluster_id: cluster.to_param, node_id: node.to_param, credential: valid_attributes }
        expect(response).to redirect_to([ cluster, node ])
      end

      it "sets a success notice" do
        post :create, params: { cluster_id: cluster.to_param, node_id: node.to_param, credential: valid_attributes }
        expect(flash[:notice]).to eq("Credential was successfully created.")
      end
    end

    context "with invalid params" do
      it "does not create a new Credential" do
        expect {
          post :create, params: { cluster_id: cluster.to_param, node_id: node.to_param, credential: invalid_attributes }
        }.not_to change(Credential, :count)
      end

      it "renders the new template" do
        post :create, params: { cluster_id: cluster.to_param, node_id: node.to_param, credential: invalid_attributes }
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PUT #update" do
    context "attempting to change username" do
      let(:new_attributes) { { username: "updateduser" } }

      it "does not update the username" do
        original_username = credential.username
        put :update, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param, credential: new_attributes }
        credential.reload
        expect(credential.username).to eq(original_username)
      end

      it "renders the edit template with error" do
        put :update, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param, credential: new_attributes }
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "attempting to change password" do
      let(:password_change_attributes) { { password: "newpassword123" } }

      it "does not update the password" do
        put :update, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param, credential: password_change_attributes }
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with invalid params" do
      it "does not update the credential" do
        original_username = credential.username
        put :update, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param, credential: invalid_attributes }
        credential.reload
        expect(credential.username).to eq(original_username)
      end

      it "renders the edit template" do
        put :update, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param, credential: invalid_attributes }
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE #destroy" do
    before do
      allow_any_instance_of(Credential).to receive(:deprovision!) do |instance|
        instance.destroy!
      end
    end

    context 'with non-default credential' do
      it "destroys the requested credential" do
        credential # create the credential
        expect {
          delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
        }.to change(Credential, :count).by(-1)
      end

      it "redirects to the cluster" do
        delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
        expect(response).to redirect_to([ cluster, node ])
      end

      it "sets a success notice" do
        delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }
        expect(flash[:notice]).to eq("Credential was successfully destroyed.")
      end
    end

    context 'with default credential' do
      let(:default_credential) { create(:credential, node: node, username: 'default', password: 'password') }

      it "does not destroy the credential" do
        default_credential # create the credential
        expect {
          delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: default_credential.to_param }
        }.not_to change(Credential, :count)
      end

      it "redirects to the node" do
        delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: default_credential.to_param }
        expect(response).to redirect_to([ cluster, node ])
      end

      it "sets an alert message" do
        delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: default_credential.to_param }
        expect(flash[:alert]).to eq("Cannot delete the default credential.")
      end
    end
  end

  # JSON format tests
  describe "JSON responses" do
    before do
      allow_any_instance_of(Credential).to receive(:provision!)
      allow_any_instance_of(Credential).to receive(:deprovision!)
    end

    describe "POST #create" do
      context "with valid params" do
        it "returns JSON with created status" do
          post :create, params: { cluster_id: cluster.to_param, node_id: node.to_param, credential: valid_attributes }, format: :json
          expect(response).to have_http_status(:created)
          expect(response.content_type).to include('application/json')
        end
      end

      context "with invalid params" do
        it "returns JSON with errors" do
          post :create, params: { cluster_id: cluster.to_param, node_id: node.to_param, credential: invalid_attributes }, format: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.content_type).to include('application/json')
        end
      end
    end

    describe "PUT #update" do
      context "attempting to change username" do
        it "returns JSON with errors" do
          put :update, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param, credential: { username: "updated" } }, format: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.content_type).to include('application/json')
        end
      end

      context "attempting to change password" do
        it "returns JSON with errors" do
          put :update, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param, credential: { password: "newpass" } }, format: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.content_type).to include('application/json')
        end
      end

      context "with invalid params" do
        it "returns JSON with errors" do
          put :update, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param, credential: invalid_attributes }, format: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.content_type).to include('application/json')
        end
      end
    end

    describe "DELETE #destroy" do
      context 'with non-default credential' do
        it "returns no content status" do
          delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: credential.to_param }, format: :json
          expect(response).to have_http_status(:no_content)
        end
      end

      context 'with default credential' do
        let(:default_credential) { create(:credential, node: node, username: 'default', password: 'password') }

        it "returns unprocessable entity status" do
          delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: default_credential.to_param }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "returns error message in JSON" do
          delete :destroy, params: { cluster_id: cluster.to_param, node_id: node.to_param, id: default_credential.to_param }, format: :json
          expect(JSON.parse(response.body)['error']).to eq("Cannot delete the default credential")
        end
      end
    end
  end

  describe "credential replication restrictions" do
    let(:mysql_database_type) { create(:database_type, slug: 'mysql', name: 'MySQL') }
    let(:mysql_cluster) { create(:cluster, database_type: mysql_database_type) }
    let(:mysql_version) { create(:database_type_version, database_type: mysql_database_type, version: '8.0') }
    let(:primary_node) { create(:node, cluster: mysql_cluster, provider: provider, database_type_version: mysql_version, parent_node: nil) }
    let(:replica_node) { create(:node, cluster: mysql_cluster, provider: provider, database_type_version: mysql_version, parent_node: primary_node, status: 'active') }

    before do
      # Mock the database type handler
      allow_any_instance_of(Node).to receive(:database_type_handler).and_return(
        double(users_replicate_automatically?: true)
      )
    end

    describe "GET #new on replica" do
      it "redirects to node page with error" do
        get :new, params: { cluster_id: mysql_cluster.to_param, node_id: replica_node.to_param }
        expect(response).to redirect_to([ mysql_cluster, replica_node ])
      end

      it "sets alert message" do
        get :new, params: { cluster_id: mysql_cluster.to_param, node_id: replica_node.to_param }
        expect(flash[:alert]).to eq("Cannot create credentials on a replica node. Create credentials on the primary node instead.")
      end
    end

    describe "GET #new on primary" do
      it "allows creating credentials" do
        get :new, params: { cluster_id: mysql_cluster.to_param, node_id: primary_node.to_param }
        expect(response).to be_successful
      end
    end

    describe "DELETE #destroy on replicated credential" do
      let(:primary_credential) do
        allow_any_instance_of(Credential).to receive(:replicate_to_replicas)
        primary_node.credentials.create!(username: 'testuser', password: 'testpass')
      end

      let(:replicated_credential) do
        replica_node.credentials.create!(
          username: 'testuser',
          password: 'testpass',
          source_credential_id: primary_credential.id,
          is_replicated: true
        )
      end

      it "redirects with error message" do
        delete :destroy, params: { cluster_id: mysql_cluster.to_param, node_id: replica_node.to_param, id: replicated_credential.to_param }
        expect(response).to redirect_to([ mysql_cluster, replica_node ])
      end

      it "sets alert message" do
        delete :destroy, params: { cluster_id: mysql_cluster.to_param, node_id: replica_node.to_param, id: replicated_credential.to_param }
        expect(flash[:alert]).to eq("Cannot delete replicated credentials. Delete the credential from the primary node instead.")
      end

      it "does not delete the credential" do
        replicated_credential # create it
        expect {
          delete :destroy, params: { cluster_id: mysql_cluster.to_param, node_id: replica_node.to_param, id: replicated_credential.to_param }
        }.not_to change { Credential.count }
      end
    end
  end
end
