require 'rails_helper'

RSpec.describe NodeMetricsController, type: :controller do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

  let(:valid_metrics_data) do
    {
      collected_at: Time.current,
      cpu_usage_percent: 45.5,
      memory_total_mb: 8192,
      memory_used_mb: 4096,
      memory_available_mb: 4096,
      swap_total_mb: 2048,
      swap_used_mb: 512,
      uptime_seconds: 86400,
      disk_usage: {
        '/' => {
          usage_percent: 65.0,
          total_gb: 100.0,
          used_gb: 65.0,
          available_gb: 35.0
        }
      },
      network_stats: {
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
      }
    }
  end

  before do
    node.ensure_metrics_api_key!
    node.update!(status: 'active')  # Node must be active to submit metrics
  end

  describe 'POST #create' do
    context 'with valid authentication' do
      before do
        request.headers['Authorization'] = "Bearer #{node.metrics_api_key}"
      end

      context 'with valid metrics data' do
        it 'creates a new node metric' do
          expect {
            post :create, params: { node_id: node.id, node_metric: valid_metrics_data }
          }.to change(NodeMetric, :count).by(1)
        end

        it 'returns success response' do
          post :create, params: { node_id: node.id, node_metric: valid_metrics_data }
          expect(response).to have_http_status(:created)
          expect(JSON.parse(response.body)).to include('success' => true)
        end

        it 'stores metrics data correctly' do
          post :create, params: { node_id: node.id, node_metric: valid_metrics_data }

          metric = NodeMetric.last
          expect(metric.node).to eq(node)
          expect(metric.cpu_usage_percent).to eq(45.5)
          expect(metric.memory_total_mb).to eq(8192)
          expect(metric.memory_used_mb).to eq(4096)
          expect(metric.disk_usage['/']).to include('usage_percent' => '65.0')
        end

        it 'broadcasts metrics update via ActionCable' do
          expect(ActionCable.server).to receive(:broadcast).at_least(:once)

          post :create, params: { node_id: node.id, node_metric: valid_metrics_data }
        end

        it 'broadcasts to cluster channel' do
          expect(ActionCable.server).to receive(:broadcast).at_least(:once)

          post :create, params: { node_id: node.id, node_metric: valid_metrics_data }
        end
      end

      context 'with invalid metrics data' do
        let(:invalid_data) do
          {
            cpu_usage_percent: 150.0, # Invalid: > 100
            memory_total_mb: -1000 # Invalid: negative
          }
        end

        it 'does not create a node metric' do
          expect {
            post :create, params: { node_id: node.id, node_metric: invalid_data }
          }.not_to change(NodeMetric, :count)
        end

        it 'returns error response' do
          post :create, params: { node_id: node.id, node_metric: invalid_data }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)).to include('success' => false)
        end

        it 'includes validation errors' do
          post :create, params: { node_id: node.id, node_metric: invalid_data }
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end

      context 'with missing required fields' do
        let(:incomplete_data) do
          {
            cpu_usage_percent: 45.5
            # Missing memory, uptime, etc.
          }
        end

        it 'returns error response' do
          post :create, params: { node_id: node.id, node_metric: incomplete_data }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context 'with invalid authentication' do
      it 'returns unauthorized for missing token' do
        post :create, params: { node_id: node.id, node_metric: valid_metrics_data }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized for invalid token' do
        request.headers['Authorization'] = "Bearer invalid_token"
        post :create, params: { node_id: node.id, node_metric: valid_metrics_data }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized for malformed authorization header' do
        request.headers['Authorization'] = "InvalidFormat token"
        post :create, params: { node_id: node.id, node_metric: valid_metrics_data }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with node that has no metrics API key' do
      before do
        node.update!(metrics_api_key: nil)
        request.headers['Authorization'] = "Bearer some_token"
      end

      it 'returns unauthorized' do
        post :create, params: { node_id: node.id, node_metric: valid_metrics_data }
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
      get :index, params: { node_id: node.id }
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body['metrics']).to be_an(Array)
      expect(body['metrics'].length).to eq(3)
    end

    it 'orders metrics by collected_at descending' do
      get :index, params: { node_id: node.id }
      body = JSON.parse(response.body)

      timestamps = body['metrics'].map { |m| Time.parse(m['collected_at']) }
      expect(timestamps).to eq(timestamps.sort.reverse)
    end

    it 'limits results when limit parameter provided' do
      get :index, params: { node_id: node.id, limit: 2 }
      body = JSON.parse(response.body)

      expect(body['metrics'].length).to eq(2)
    end

    it 'filters by time range when since parameter provided' do
      get :index, params: { node_id: node.id, since: 90.minutes.ago.iso8601 }
      body = JSON.parse(response.body)

      expect(body['metrics'].length).to eq(2) # metric2 and metric3
    end

    it 'requires authentication' do
      request.headers['Authorization'] = nil
      get :index, params: { node_id: node.id }
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
      get :latest, params: { node_id: node.id }
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body['id']).to eq(latest_metric.id)
    end

    it 'returns 404 when no metrics exist' do
      NodeMetric.destroy_all
      get :latest, params: { node_id: node.id }
      expect(response).to have_http_status(:not_found)
    end

    it 'requires authentication' do
      request.headers['Authorization'] = nil
      get :latest, params: { node_id: node.id }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
