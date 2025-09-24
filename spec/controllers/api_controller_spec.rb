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

    context "when provider not found" do
      it "raises ActiveRecord::RecordNotFound" do
        allow(Provider).to receive(:find).and_raise(ActiveRecord::RecordNotFound)

        expect {
          get :index, params: { provider_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when api client raises an error" do
      it "allows the error to bubble up" do
        allow(mock_client).to receive(:call).and_raise(StandardError, "API Error")

        expect {
          get :index, params: { provider_id: provider.id }
        }.to raise_error(StandardError, "API Error")
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
  end
end
