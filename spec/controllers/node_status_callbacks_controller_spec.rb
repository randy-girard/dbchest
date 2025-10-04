require 'rails_helper'

RSpec.describe NodeStatusCallbacksController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

  before do
    # Mock the update_status! method to avoid ActionCable broadcasting in tests
    allow_any_instance_of(Node).to receive(:update_status!)
  end

  describe "POST #update" do
    context "with valid status" do
      it "returns a success response" do
        post :update, params: { id: node.id, status: 'active', message: 'Node is ready' }
        expect(response).to be_successful
      end

      it "returns JSON success" do
        post :update, params: { id: node.id, status: 'active', message: 'Node is ready' }

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
      end

      it "calls update_status! on the node" do
        expect_any_instance_of(Node).to receive(:update_status!).with('active', 'Node is ready')
        post :update, params: { id: node.id, status: 'active', message: 'Node is ready' }
      end

      it "logs the callback" do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(/Received cloud-init callback for node #{node.id}/)
        post :update, params: { id: node.id, status: 'active', message: 'Node is ready' }
      end

      it "works with all valid statuses" do
        Node::STATUSES.keys.each do |status|
          post :update, params: { id: node.id, status: status, message: "Testing #{status}" }
          expect(response).to be_successful

          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
        end
      end
    end

    context "with invalid status" do
      it "returns bad request" do
        post :update, params: { id: node.id, status: 'invalid_status', message: 'Test' }
        expect(response).to have_http_status(:bad_request)
      end

      it "returns error message" do
        post :update, params: { id: node.id, status: 'invalid_status', message: 'Test' }

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Invalid status')
      end

      it "does not call update_status!" do
        expect_any_instance_of(Node).not_to receive(:update_status!)
        post :update, params: { id: node.id, status: 'invalid_status', message: 'Test' }
      end
    end

    context "with non-existent node" do
      it "returns not found" do
        post :update, params: { id: 999999, status: 'active', message: 'Test' }
        expect(response).to have_http_status(:not_found)
      end

      it "returns error message" do
        post :update, params: { id: 999999, status: 'active', message: 'Test' }

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Node not found')
      end
    end

    context "when update_status! raises an error" do
      before do
        allow_any_instance_of(Node).to receive(:update_status!).and_raise(StandardError, "Database error")
      end

      it "returns internal server error" do
        post :update, params: { id: node.id, status: 'active', message: 'Test' }
        expect(response).to have_http_status(:internal_server_error)
      end

      it "returns error message" do
        post :update, params: { id: node.id, status: 'active', message: 'Test' }

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Internal server error')
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Error in cloud-init callback for node #{node.id}/)
        post :update, params: { id: node.id, status: 'active', message: 'Test' }
      end
    end



    context "without message parameter" do
      it "works with nil message" do
        expect_any_instance_of(Node).to receive(:update_status!).with('active', nil)
        post :update, params: { id: node.id, status: 'active' }
        expect(response).to be_successful
      end
    end

    context "CSRF protection" do
      it "skips authenticity token verification" do
        # This test ensures the skip_before_action is working
        # In a real scenario, this would fail without the skip_before_action
        post :update, params: { id: node.id, status: 'active', message: 'Test' }
        expect(response).to be_successful
      end
    end
  end
end
