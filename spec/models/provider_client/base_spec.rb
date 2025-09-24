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
end
