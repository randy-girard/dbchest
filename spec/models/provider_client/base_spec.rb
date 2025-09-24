require 'rails_helper'

RSpec.describe ProviderClient::Base, type: :model do
  let(:settings) { double('settings', api_url: 'http://example.com') }
  let(:client) { described_class.new(settings) }

  describe '#initialize' do
    it 'sets the settings' do
      expect(client.settings).to eq(settings)
    end
  end

  describe '#call' do
    context 'when function exists' do
      before do
        # Define a test method on the client instance
        def client.test_function(params)
          'result'
        end
      end

      it 'calls the function with params' do
        params = { function: :test_function, arg1: 'value1' }
        expect(client).to receive(:test_function).with(params).and_call_original
        client.call(params)
      end

      it 'returns the function result' do
        params = { function: :test_function }
        result = client.call(params)
        expect(result).to eq('result')
      end
    end

    context 'when function does not exist' do
      it 'returns nil' do
        params = { function: :nonexistent_function }
        result = client.call(params)
        expect(result).to be_nil
      end
    end

    context 'when function parameter is missing' do
      it 'handles nil function gracefully' do
        params = { arg1: 'value1' }
        result = client.call(params)
        expect(result).to be_nil
      end
    end
  end

  describe 'registry methods' do
    describe '.register' do
      it 'registers a provider client' do
        test_client = Class.new(described_class)
        described_class.register('test_provider', test_client)

        expect(described_class.registered_types).to include('test_provider')
      end
    end

    describe '.for_provider' do
      let(:provider_type) { double('provider_type', key: 'test_provider') }
      let(:provider) { double('provider', provider_type: provider_type, provider_settings_object: settings) }
      let(:test_client_class) { Class.new(described_class) }

      before do
        described_class.register('test_provider', test_client_class)
      end

      it 'returns correct client instance' do
        client = described_class.for_provider(provider)
        expect(client).to be_a(test_client_class)
      end

      it 'raises error for unknown provider type' do
        unknown_provider_type = double('provider_type', key: 'unknown')
        unknown_provider = double('provider', provider_type: unknown_provider_type)

        expect {
          described_class.for_provider(unknown_provider)
        }.to raise_error(ArgumentError, /Unknown provider type: unknown/)
      end
    end

    describe '.registered_types' do
      it 'returns list of registered provider types' do
        types = described_class.registered_types
        expect(types).to include('proxmox')
      end
    end
  end

  describe 'abstract methods' do
    describe '#exists?' do
      it 'raises NotImplementedError' do
        expect {
          client.exists?(double('node'))
        }.to raise_error(NotImplementedError, /must implement #exists?/)
      end
    end

    describe '#nodes' do
      it 'raises NotImplementedError' do
        expect {
          client.nodes
        }.to raise_error(NotImplementedError, /must implement #nodes/)
      end
    end

    describe '#storage' do
      it 'raises NotImplementedError' do
        expect {
          client.storage
        }.to raise_error(NotImplementedError, /must implement #storage/)
      end
    end
  end
end
