require 'rails_helper'

RSpec.describe NodesStatusController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let!(:nodes) do
    [
      create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'active'),
      create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'pending'),
      create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'provisioning')
    ]
  end

  describe "GET #index" do
    context "with JSON format" do
      it "returns a success response" do
        get :index, params: { cluster_id: cluster.id }, format: :json
        expect(response).to be_successful
      end

      it "assigns the cluster" do
        get :index, params: { cluster_id: cluster.id }, format: :json
        expect(assigns(:cluster)).to eq(cluster)
      end

      it "assigns nodes with selected fields" do
        get :index, params: { cluster_id: cluster.id }, format: :json
        expect(assigns(:nodes)).to match_array(nodes)
      end

      it "returns JSON with node data" do
        get :index, params: { cluster_id: cluster.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response).to be_an(Array)
        expect(json_response.length).to eq(3)
        
        node_data = json_response.first
        expect(node_data).to have_key('id')
        expect(node_data).to have_key('name')
        expect(node_data).to have_key('status')
        expect(node_data).to have_key('status_display')
        expect(node_data).to have_key('status_badge_class')
        expect(node_data).to have_key('updated_at')
      end

      it "includes status display methods" do
        get :index, params: { cluster_id: cluster.id }, format: :json
        
        json_response = JSON.parse(response.body)
        active_node = json_response.find { |n| n['status'] == 'active' }
        
        expect(active_node['status_display']).to be_present
        expect(active_node['status_badge_class']).to be_present
      end

      it "formats updated_at as ISO8601" do
        get :index, params: { cluster_id: cluster.id }, format: :json
        
        json_response = JSON.parse(response.body)
        node_data = json_response.first
        
        expect(node_data['updated_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it "returns correct content type" do
        get :index, params: { cluster_id: cluster.id }, format: :json
        expect(response.content_type).to include('application/json')
      end
    end

    context "with non-JSON format" do
      it "does not respond to HTML format" do
        expect {
          get :index, params: { cluster_id: cluster.id }, format: :html
        }.to raise_error(ActionController::UnknownFormat)
      end
    end

    context "with non-existent cluster" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :index, params: { cluster_id: 999999 }, format: :json
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "with empty cluster" do
      let(:empty_cluster) { create(:cluster, database_type: database_type) }

      it "returns empty array" do
        get :index, params: { cluster_id: empty_cluster.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response).to eq([])
      end
    end
  end

  describe "GET #show" do
    let(:node) { nodes.first }

    context "with JSON format" do
      it "returns a success response" do
        get :show, params: { id: node.id }, format: :json
        expect(response).to be_successful
      end

      it "returns node status data" do
        get :show, params: { id: node.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response['id']).to eq(node.id)
        expect(json_response['name']).to eq(node.name)
        expect(json_response['status']).to eq(node.status)
        expect(json_response['status_display']).to be_present
        expect(json_response['status_badge_class']).to be_present
        expect(json_response['updated_at']).to be_present
      end

      it "returns correct content type" do
        get :show, params: { id: node.id }, format: :json
        expect(response.content_type).to include('application/json')
      end
    end

    context "with non-existent node" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :show, params: { id: 999999 }, format: :json
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
