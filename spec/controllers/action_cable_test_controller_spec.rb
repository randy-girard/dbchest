require 'rails_helper'

RSpec.describe ActionCableTestController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

  before do
    # Mock the update_status! method to avoid ActionCable broadcasting in tests
    allow_any_instance_of(Node).to receive(:update_status!)
  end

  describe "GET #index" do
    context "when nodes exist" do
      it "returns a success response" do
        node # create the node
        get :index
        expect(response).to be_successful
      end

      it "assigns the first node" do
        node # create the node
        get :index
        expect(assigns(:node)).to eq(node)
      end
    end

    context "when no nodes exist" do
      it "redirects to root path" do
        get :index
        expect(response).to redirect_to(root_path)
      end

      it "sets an alert message" do
        get :index
        expect(flash[:alert]).to include("No nodes found")
      end
    end
  end

  describe "POST #broadcast_test" do
    it "returns a success response" do
      post :broadcast_test, params: { id: node.id }
      expect(response).to be_successful
    end

    it "returns JSON response" do
      post :broadcast_test, params: { id: node.id }
      expect(response.content_type).to include('application/json')
    end

    it "calls update_status! on the node" do
      expect_any_instance_of(Node).to receive(:update_status!).with('active', anything)
      post :broadcast_test, params: { id: node.id }
    end

    it "returns success JSON with node data" do
      post :broadcast_test, params: { id: node.id }

      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be true
      expect(json_response['node_id']).to eq(node.id)
      expect(json_response['status']).to eq(node.status)
      expect(json_response['message']).to be_present
    end

    it "uses a random test message" do
      post :broadcast_test, params: { id: node.id }

      json_response = JSON.parse(response.body)
      message = json_response['message']

      expect(message).to include("Broadcast sent:")
      expect(message).to match(/Testing ActionCable broadcast|This is a test message|Broadcasting to all streams|Check your browser console/)
    end

    it "assigns the node" do
      post :broadcast_test, params: { id: node.id }
      expect(assigns(:node)).to eq(node)
    end

    context "with non-existent node" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          post :broadcast_test, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when update_status! raises an error" do
      before do
        allow_any_instance_of(Node).to receive(:update_status!).and_raise(StandardError, "Broadcast error")
      end

      it "allows the error to bubble up" do
        expect {
          post :broadcast_test, params: { id: node.id }
        }.to raise_error(StandardError, "Broadcast error")
      end
    end
  end
end
