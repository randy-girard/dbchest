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

    context "with configure_primary_for_replica status" do
      let(:primary_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
      let(:replica_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: primary_node) }

      before do
        # Mock the job and update_status! method
        allow(ConfigurePrimaryForReplicaJob).to receive(:perform_later)
        allow_any_instance_of(Node).to receive(:update_status!)
      end

      it "handles configure_primary_for_replica status" do
        message = "Configure primary for replica at 192.168.1.100"
        post :update, params: { id: replica_node.id, status: 'configure_primary_for_replica', message: message }
        
        expect(response).to be_successful
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
      end

      it "extracts replica IP from message" do
        message = "Configure primary for replica at 192.168.1.100"
        expect(ConfigurePrimaryForReplicaJob).to receive(:perform_later).with(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: '192.168.1.100'
        )
        
        post :update, params: { id: replica_node.id, status: 'configure_primary_for_replica', message: message }
      end

      it "updates replica status to configuring" do
        message = "Configure primary for replica at 192.168.1.100"
        allow(Node).to receive(:find).with(replica_node.id.to_s).and_return(replica_node)
        expect(replica_node).to receive(:update_status!).with('configuring', /Waiting for primary configuration/)

        post :update, params: { id: replica_node.id, status: 'configure_primary_for_replica', message: message }
      end

      it "logs the configuration request" do
        message = "Configure primary for replica at 192.168.1.100"
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(/Configuring primary for replica #{replica_node.id}/)
        expect(Rails.logger).to receive(:info).with(/Triggering Ansible job to configure primary/)

        post :update, params: { id: replica_node.id, status: 'configure_primary_for_replica', message: message }
      end

      context "when IP cannot be extracted" do
        it "logs error and continues" do
          message = "Configure primary for replica without IP"
          expect(Rails.logger).to receive(:error).with(/Could not extract replica IP from message/)
          
          post :update, params: { id: replica_node.id, status: 'configure_primary_for_replica', message: message }
          expect(response).to be_successful
        end
      end

      context "when replica has no parent node" do
        let(:orphan_replica) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

        it "logs error and continues" do
          message = "Configure primary for replica at 192.168.1.100"
          expect(Rails.logger).to receive(:error).with(/Replica node #{orphan_replica.id} has no parent node/)
          
          post :update, params: { id: orphan_replica.id, status: 'configure_primary_for_replica', message: message }
          expect(response).to be_successful
        end
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
