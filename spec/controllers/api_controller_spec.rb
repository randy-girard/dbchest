require 'rails_helper'

RSpec.describe ApiController, type: :controller do
  let(:provider) { create(:provider) }
  let(:mock_client) { double('ApiClient') }
  let(:mock_data) { { 'status' => 'success', 'data' => { 'nodes' => [] } } }

  before do
    allow(provider).to receive(:api_client).and_return(mock_client)
    allow(Provider).to receive(:find).and_return(provider)
  end

  describe "GET #index" do
    it "returns a success response" do
      allow(mock_client).to receive(:call).and_return(mock_data)

      get :index, params: { provider_id: provider.id }
      expect(response).to be_successful
    end

    it "assigns the provider" do
      allow(mock_client).to receive(:call).and_return(mock_data)

      get :index, params: { provider_id: provider.id }
      expect(assigns(:provider)).to eq(provider)
    end

    it "assigns the api client" do
      allow(mock_client).to receive(:call).and_return(mock_data)

      get :index, params: { provider_id: provider.id }
      expect(assigns(:client)).to eq(mock_client)
    end

    it "calls the api client with params" do
      expect(mock_client).to receive(:call) do |passed_params|
        expect(passed_params).to be_a(ActionController::Parameters)
        expect(passed_params[:provider_id]).to eq(provider.id.to_s)
        expect(passed_params[:test]).to eq('value')
        mock_data
      end

      get :index, params: { provider_id: provider.id, test: 'value' }
    end

    it "assigns the api data" do
      allow(mock_client).to receive(:call).and_return(mock_data)

      get :index, params: { provider_id: provider.id }
      expect(assigns(:data)).to eq(mock_data)
    end

    it "returns JSON response" do
      allow(mock_client).to receive(:call).and_return(mock_data)

      get :index, params: { provider_id: provider.id }
      expect(response.content_type).to include('application/json')

      json_response = JSON.parse(response.body)
      expect(json_response).to eq(mock_data)
    end

    it "logs the api data" do
      allow(mock_client).to receive(:call).and_return(mock_data)
      allow(Rails.logger).to receive(:info) # Allow other log calls
      expect(Rails.logger).to receive(:info).with(mock_data.inspect)

      get :index, params: { provider_id: provider.id }
    end



    context "when api client is nil" do
      before do
        allow(provider).to receive(:api_client).and_return(nil)
      end

      it "returns unprocessable_content status" do
        get :index, params: { provider_id: provider.id }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns error message in JSON" do
        get :index, params: { provider_id: provider.id }
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Provider client not available')
      end

      it "logs error message" do
        expect(Rails.logger).to receive(:error).with(/No API client available/)
        get :index, params: { provider_id: provider.id }
      end
    end

    context "when api client raises an error" do
      it "returns internal_server_error status" do
        allow(mock_client).to receive(:call).and_raise(StandardError, "API Error")

        get :index, params: { provider_id: provider.id }
        expect(response).to have_http_status(:internal_server_error)
      end

      it "returns error message in JSON" do
        allow(mock_client).to receive(:call).and_raise(StandardError, "API Error")

        get :index, params: { provider_id: provider.id }
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('API call failed: API Error')
      end

      it "logs error message" do
        allow(mock_client).to receive(:call).and_raise(StandardError, "API Error")
        expect(Rails.logger).to receive(:error).with('API call failed: API Error')

        get :index, params: { provider_id: provider.id }
      end
    end

    context "with additional parameters" do
      it "passes all parameters to the api client" do
        params = {
          provider_id: provider.id,
          custom_action: 'list_nodes',
          filter: 'active',
          limit: 10
        }

        expect(mock_client).to receive(:call) do |passed_params|
          expect(passed_params[:custom_action]).to eq('list_nodes')
          expect(passed_params[:filter]).to eq('active')
          expect(passed_params[:limit]).to eq('10')
          mock_data
        end

        get :index, params: params
      end
    end

    context "with real provider client integration" do
      let(:provider_type) { create(:provider_type, key: 'proxmox') }
      let(:real_provider) { create(:provider, provider_type: provider_type) }

      before do
        # Clear the mocks from the outer scope for these tests
        allow(Provider).to receive(:find).and_call_original
      end

      it "works with registered provider client" do
        # Mock the actual Proxmox client call
        mock_proxmox_client = double('ProxmoxClient')
        allow(ProviderClient::Base).to receive(:for_provider).with(real_provider).and_return(mock_proxmox_client)
        allow(mock_proxmox_client).to receive(:call).and_return({ 'nodes' => [ 'pve1', 'pve2' ] })

        get :index, params: { provider_id: real_provider.id, function: 'nodes' }

        expect(response).to be_successful
        json_response = JSON.parse(response.body)
        expect(json_response['nodes']).to eq([ 'pve1', 'pve2' ])
      end

      it "handles unknown provider type gracefully" do
        unknown_provider_type = create(:provider_type, key: 'unknown_provider')
        unknown_provider = create(:provider, provider_type: unknown_provider_type)

        get :index, params: { provider_id: unknown_provider.id, function: 'nodes' }

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Provider client not available')
      end
    end
  end
end
