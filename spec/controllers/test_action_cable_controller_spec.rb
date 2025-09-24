require 'rails_helper'

RSpec.describe TestActionCableController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

  before do
    # Mock the update_status! method to avoid ActionCable broadcasting in tests
    allow_any_instance_of(Node).to receive(:update_status!)
  end

  describe "GET #show" do
    it "returns a success response" do
      get :show, params: { node_id: node.id }
      expect(response).to be_successful
    end

    it "assigns the node" do
      get :show, params: { node_id: node.id }
      expect(assigns(:node)).to eq(node)
    end

    it "assigns test statuses" do
      get :show, params: { node_id: node.id }
      test_statuses = assigns(:test_statuses)
      
      expect(test_statuses).to be_an(Array)
      expect(test_statuses.length).to eq(5)
      
      # Check that all expected statuses are present
      statuses = test_statuses.map { |ts| ts[:status] }
      expect(statuses).to include('pending', 'provisioning', 'configuring', 'active', 'destroying')
      
      # Check that all have messages
      test_statuses.each do |ts|
        expect(ts[:message]).to be_present
        expect(ts[:message]).to include('Test:')
      end
    end

    context "with non-existent node" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :show, params: { node_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "POST #update_status" do
    context "with valid parameters" do
      it "returns a success response" do
        post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }
        expect(response).to have_http_status(:found) # redirect response
      end

      it "calls update_status! on the node" do
        expect_any_instance_of(Node).to receive(:update_status!).with('active', 'Test message')
        post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }
      end

      it "assigns the node" do
        post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }
        expect(assigns(:node)).to eq(node)
      end

      context "with JSON format" do
        it "returns JSON success response" do
          post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }, format: :json
          
          expect(response).to be_successful
          expect(response.content_type).to include('application/json')
          
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
          expect(json_response['node_id']).to eq(node.id)
          expect(json_response['status']).to eq(node.status)
          expect(json_response['message']).to include("Status updated to 'active'")
        end
      end

      context "with HTML format" do
        it "redirects to cluster path" do
          post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }
          expect(response).to redirect_to(cluster_path(node.cluster))
        end

        it "sets a success notice" do
          post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }
          expect(flash[:notice]).to include("✅ Test: Updated #{node.name} to 'active'")
        end
      end

      context "with default parameters" do
        it "uses default status when not provided" do
          expect_any_instance_of(Node).to receive(:update_status!).with('provisioning', anything)
          post :update_status, params: { node_id: node.id }
        end

        it "uses default message when not provided" do
          expect_any_instance_of(Node).to receive(:update_status!).with(anything, "Test update from web interface")
          post :update_status, params: { node_id: node.id }
        end
      end

      it "logs the test update" do
        allow(Rails.logger).to receive(:info) # Allow other log calls
        expect(Rails.logger).to receive(:info).with(/🧪 Web test: Updating node #{node.id} to status 'active'/)
        post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }
      end
    end

    context "when update_status! raises an error" do
      before do
        allow_any_instance_of(Node).to receive(:update_status!).and_raise(StandardError, "Update failed")
      end

      context "with JSON format" do
        it "returns JSON error response" do
          post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }, format: :json
          
          expect(response).to be_successful
          expect(response.content_type).to include('application/json')
          
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be false
          expect(json_response['error']).to eq("Update failed")
        end
      end

      context "with HTML format" do
        it "redirects with alert" do
          post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }
          expect(response).to redirect_to(cluster_path(node.cluster))
          expect(flash[:alert]).to include("❌ Error: Update failed")
        end
      end
    end

    context "with non-existent node" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          post :update_status, params: { node_id: 999999, status: 'active', message: 'Test message' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "with redirect_back fallback" do
      it "uses cluster path as fallback when no referrer" do
        post :update_status, params: { node_id: node.id, status: 'active', message: 'Test message' }
        expect(response).to redirect_to(cluster_path(node.cluster))
      end
    end
  end
end
