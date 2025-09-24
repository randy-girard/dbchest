require 'rails_helper'

RSpec.describe DevelopmentConsoleChannel, type: :channel do
  describe '#subscribed' do
    context 'in development environment' do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
      end

      it 'subscribes to development console stream' do
        subscribe
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from('development_console')
      end

      it 'logs subscription' do
        expect(Rails.logger).to receive(:info).with('DevelopmentConsoleChannel: Client subscribed to development console')
        subscribe
      end
    end

    context 'in non-development environment' do
      before do
        allow(Rails.env).to receive(:development?).and_return(false)
      end

      it 'rejects the subscription' do
        subscribe
        expect(subscription).to be_rejected
      end

      it 'does not subscribe to any stream' do
        subscribe
        expect(subscription.streams).to be_empty
      end
    end
  end

  describe '#unsubscribed' do
    before do
      allow(Rails.env).to receive(:development?).and_return(true)
      subscribe
    end

    it 'logs unsubscription' do
      expect(Rails.logger).to receive(:info).with('DevelopmentConsoleChannel: Client unsubscribed from development console')
      subscription.unsubscribe_from_channel
    end
  end
end
