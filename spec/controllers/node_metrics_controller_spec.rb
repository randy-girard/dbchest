require 'rails_helper'

RSpec.describe NodeMetricsController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  
  let(:valid_metrics_data) do
    {
      cpu: {
        usage_percent: 45.5
      },
      memory: {
        total_mb: 8192,
        used_mb: 4096,
        available_mb: 4096
      },
      swap: {
        total_mb: 2048,
        used_mb: 512
      },
      disk: {
        '/' => {
          usage_percent: 65.0,
          total_gb: 100.0,
          used_gb: 65.0,
          available_gb: 35.0
        }
      },
      network: {
        'eth0' => {
          rx_bytes: 1024000,
          tx_bytes: 512000,
          rx_packets: 1000,
          tx_packets: 800
        }
      },
      load_average: {
        '1min' => 1.5,
        '5min' => 1.2,
        '15min' => 1.0
      },
      uptime: {
        seconds: 86400
      }
    }
  end

  before do
    node.ensure_metrics_api_key!
  end

  describe 'POST #create' do
    context 'with valid authentication' do
      before do
        request.headers['Authorization'] = "Bearer #{node.metrics_api_key}"
      end

      context 'with valid metrics data' do
        it 'creates a new node metric' do
          expect {
            post :create, params: { metrics: valid_metrics_data }
          }.to change(NodeMetric, :count).by(1)
        end

        it 'returns success response' do
          post :create, params: { metrics: valid_metrics_data }
          expect(response).to have_http_status(:created)
          expect(JSON.parse(response.body)).to include('status' => 'success')
        end

        it 'stores metrics data correctly' do
          post :create, params: { metrics: valid_metrics_data }
          
          metric = NodeMetric.last
          expect(metric.node).to eq(node)
          expect(metric.cpu_usage_percent).to eq(45.5)
          expect(metric.memory_total_mb).to eq(8192)
          expect(metric.memory_used_mb).to eq(4096)
          expect(metric.disk_usage['/']).to include('usage_percent' => 65.0)
        end

        it 'broadcasts metrics update via ActionCable' do
          expect(ActionCable.server).to receive(:broadcast).with(
            "node_metrics_#{node.id}",
            hash_including(
              type: 'metrics_update',
              node_id: node.id,
              cluster_id: cluster.id
            )
          )
          
          post :create, params: { metrics: valid_metrics_data }
        end

        it 'broadcasts to cluster channel' do
          expect(ActionCable.server).to receive(:broadcast).with(
            "cluster_metrics_#{cluster.id}",
            hash_including(
              type: 'metrics_update',
              node_id: node.id,
              cluster_id: cluster.id
            )
          )
          
          post :create, params: { metrics: valid_metrics_data }
        end
      end

      context 'with invalid metrics data' do
        let(:invalid_data) do
          {
            cpu: {
              usage_percent: 150.0 # Invalid: > 100
            },
            memory: {
              total_mb: -1000 # Invalid: negative
            }
          }
        end

        it 'does not create a node metric' do
          expect {
            post :create, params: { metrics: invalid_data }
          }.not_to change(NodeMetric, :count)
        end

        it 'returns error response' do
          post :create, params: { metrics: invalid_data }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)).to include('status' => 'error')
        end

        it 'includes validation errors' do
          post :create, params: { metrics: invalid_data }
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end

      context 'with missing required fields' do
        let(:incomplete_data) do
          {
            cpu: {
              usage_percent: 45.5
            }
            # Missing memory, uptime, etc.
          }
        end

        it 'returns error response' do
          post :create, params: { metrics: incomplete_data }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context 'with invalid authentication' do
      it 'returns unauthorized for missing token' do
        post :create, params: { metrics: valid_metrics_data }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized for invalid token' do
        request.headers['Authorization'] = "Bearer invalid_token"
        post :create, params: { metrics: valid_metrics_data }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized for malformed authorization header' do
        request.headers['Authorization'] = "InvalidFormat token"
        post :create, params: { metrics: valid_metrics_data }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with node that has no metrics API key' do
      before do
        node.update!(metrics_api_key: nil)
        request.headers['Authorization'] = "Bearer some_token"
      end

      it 'returns unauthorized' do
        post :create, params: { metrics: valid_metrics_data }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET #index' do
    let!(:metric1) { create(:node_metric, node: node, collected_at: 2.hours.ago) }
    let!(:metric2) { create(:node_metric, node: node, collected_at: 1.hour.ago) }
    let!(:metric3) { create(:node_metric, node: node, collected_at: 30.minutes.ago) }

    before do
      request.headers['Authorization'] = "Bearer #{node.metrics_api_key}"
    end

    it 'returns metrics for the authenticated node' do
      get :index
      expect(response).to have_http_status(:ok)
      
      body = JSON.parse(response.body)
      expect(body['metrics']).to be_an(Array)
      expect(body['metrics'].length).to eq(3)
    end

    it 'orders metrics by collected_at descending' do
      get :index
      body = JSON.parse(response.body)
      
      timestamps = body['metrics'].map { |m| Time.parse(m['collected_at']) }
      expect(timestamps).to eq(timestamps.sort.reverse)
    end

    it 'limits results when limit parameter provided' do
      get :index, params: { limit: 2 }
      body = JSON.parse(response.body)
      
      expect(body['metrics'].length).to eq(2)
    end

    it 'filters by time range when since parameter provided' do
      get :index, params: { since: 90.minutes.ago.iso8601 }
      body = JSON.parse(response.body)
      
      expect(body['metrics'].length).to eq(2) # metric2 and metric3
    end

    it 'requires authentication' do
      request.headers.delete('Authorization')
      get :index
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET #latest' do
    let!(:latest_metric) { create(:node_metric, node: node, collected_at: 30.minutes.ago) }
    let!(:older_metric) { create(:node_metric, node: node, collected_at: 2.hours.ago) }

    before do
      request.headers['Authorization'] = "Bearer #{node.metrics_api_key}"
    end

    it 'returns the latest metric for the node' do
      get :latest
      expect(response).to have_http_status(:ok)
      
      body = JSON.parse(response.body)
      expect(body['metric']['id']).to eq(latest_metric.id)
    end

    it 'returns 404 when no metrics exist' do
      NodeMetric.destroy_all
      get :latest
      expect(response).to have_http_status(:not_found)
    end

    it 'requires authentication' do
      request.headers.delete('Authorization')
      get :latest
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'private methods' do
    describe '#authenticate_node' do
      controller do
        def test_action
          authenticate_node
          render json: { node_id: @current_node.id }
        end
      end

      before do
        routes.draw { get 'test_action' => 'node_metrics#test_action' }
      end

      it 'sets @current_node for valid token' do
        request.headers['Authorization'] = "Bearer #{node.metrics_api_key}"
        get :test_action
        
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['node_id']).to eq(node.id)
      end

      it 'returns unauthorized for invalid token' do
        request.headers['Authorization'] = "Bearer invalid_token"
        get :test_action
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe '#build_node_metric' do
      let(:controller_instance) { NodeMetricsController.new }
      
      before do
        controller_instance.instance_variable_set(:@current_node, node)
        controller_instance.params = ActionController::Parameters.new(metrics: valid_metrics_data)
      end

      it 'builds node metric with correct attributes' do
        metric = controller_instance.send(:build_node_metric)
        
        expect(metric.node).to eq(node)
        expect(metric.cpu_usage_percent).to eq(45.5)
        expect(metric.memory_total_mb).to eq(8192)
        expect(metric.uptime_seconds).to eq(86400)
      end

      it 'sets collected_at to current time' do
        freeze_time do
          metric = controller_instance.send(:build_node_metric)
          expect(metric.collected_at).to be_within(1.second).of(Time.current)
        end
      end
    end
  end
end
