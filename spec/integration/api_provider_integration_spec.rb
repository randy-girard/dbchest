require 'rails_helper'

RSpec.describe "API Provider Integration", type: :request do
  let(:provider_type) { create(:provider_type, key: 'proxmox') }
  let(:provider) { create(:provider, provider_type: provider_type) }

  describe "GET /api/providers/:provider_id" do
    context "with valid provider and registered client" do
      it "returns successful response when client call succeeds" do
        # Mock the Proxmox client to return test data
        mock_client = double('ProxmoxClient')
        allow(ProviderClient::Base).to receive(:for_provider).with(provider).and_return(mock_client)
        allow(mock_client).to receive(:call).and_return({ 'nodes' => [ 'pve1', 'pve2' ] })

        get "/api/providers/#{provider.id}", params: { function: 'nodes' }

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('application/json')

        json_response = JSON.parse(response.body)
        expect(json_response['nodes']).to eq([ 'pve1', 'pve2' ])
      end

      it "handles client errors gracefully" do
        # Mock the Proxmox client to raise an error
        mock_client = double('ProxmoxClient')
        allow(ProviderClient::Base).to receive(:for_provider).with(provider).and_return(mock_client)
        allow(mock_client).to receive(:call).and_raise(StandardError, "Connection failed")

        get "/api/providers/#{provider.id}", params: { function: 'nodes' }

        expect(response).to have_http_status(:internal_server_error)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('API call failed: Connection failed')
      end
    end

    context "with unknown provider type" do
      let(:unknown_provider_type) { create(:provider_type, key: 'unknown_provider') }
      let(:unknown_provider) { create(:provider, provider_type: unknown_provider_type) }

      it "returns error when provider client is not available" do
        get "/api/providers/#{unknown_provider.id}", params: { function: 'nodes' }

        expect(response).to have_http_status(:unprocessable_content)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Provider client not available')
      end
    end

    # Note: ActiveRecord::RecordNotFound is handled by Rails and returns 404
    # This is tested at the framework level, not in our application tests

    context "with different function parameters" do
      it "passes function parameter to client" do
        mock_client = double('ProxmoxClient')
        allow(ProviderClient::Base).to receive(:for_provider).with(provider).and_return(mock_client)

        expect(mock_client).to receive(:call) do |params|
          expect(params[:function]).to eq('storage')
          expect(params[:node]).to eq('pve1')
          { 'storage' => [ 'local', 'shared' ] }
        end

        get "/api/providers/#{provider.id}", params: { function: 'storage', node: 'pve1' }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['storage']).to eq([ 'local', 'shared' ])
      end
    end
  end

  describe "Provider Client Registration" do
    it "has proxmox client registered" do
      expect(ProviderClient::Base.registered_types).to include('proxmox')
    end

    it "can create proxmox client for provider" do
      client = ProviderClient::Base.for_provider(provider)
      expect(client).to be_a(ProviderClient::Proxmox)
    end

    it "raises error for unknown provider type" do
      unknown_provider_type = create(:provider_type, key: 'unknown')
      unknown_provider = create(:provider, provider_type: unknown_provider_type)

      expect {
        ProviderClient::Base.for_provider(unknown_provider)
      }.to raise_error(ArgumentError, /Unknown provider type: unknown/)
    end
  end
end
