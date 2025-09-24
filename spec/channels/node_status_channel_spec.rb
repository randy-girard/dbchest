require 'rails_helper'

RSpec.describe NodeStatusChannel, type: :channel do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:node) { create(:node, cluster: cluster, database_type_version: database_type_version) }

  describe '#subscribed' do
    context 'without parameters' do
      it 'subscribes to general node status updates' do
        subscribe
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from('node_status_updates')
      end
    end

    context 'with node_id parameter' do
      it 'subscribes to specific node updates' do
        subscribe(node_id: node.id)
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from('node_status_updates')
        expect(subscription).to have_stream_from("node_status_#{node.id}")
      end
    end

    context 'with cluster_id parameter' do
      it 'subscribes to cluster updates' do
        subscribe(cluster_id: cluster.id)
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from('node_status_updates')
        expect(subscription).to have_stream_from("cluster_#{cluster.id}_node_status")
      end
    end

    context 'with both node_id and cluster_id parameters' do
      it 'subscribes to both streams' do
        subscribe(node_id: node.id, cluster_id: cluster.id)
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from('node_status_updates')
        expect(subscription).to have_stream_from("node_status_#{node.id}")
        expect(subscription).to have_stream_from("cluster_#{cluster.id}_node_status")
      end
    end
  end

  describe '#unsubscribed' do
    it 'logs unsubscription' do
      subscribe
      expect(Rails.logger).to receive(:info).with('NodeStatusChannel: Client unsubscribed')
      subscription.unsubscribe_from_channel
    end
  end

  describe '#subscribe_to_node' do
    before { subscribe }

    context 'with valid node_id' do
      it 'subscribes to specific node stream' do
        perform :subscribe_to_node, node_id: node.id
        expect(subscription).to have_stream_from("node_status_#{node.id}")
      end
    end

    context 'with empty node_id' do
      it 'does not subscribe to any stream' do
        initial_streams = subscription.streams.dup
        perform :subscribe_to_node, node_id: ''
        expect(subscription.streams).to eq(initial_streams)
      end
    end

    context 'with nil node_id' do
      it 'does not subscribe to any stream' do
        initial_streams = subscription.streams.dup
        perform :subscribe_to_node, node_id: nil
        expect(subscription.streams).to eq(initial_streams)
      end
    end
  end

  describe '#subscribe_to_cluster' do
    before { subscribe }

    context 'with valid cluster_id' do
      it 'subscribes to cluster stream' do
        perform :subscribe_to_cluster, cluster_id: cluster.id
        expect(subscription).to have_stream_from("cluster_#{cluster.id}_node_status")
      end
    end

    context 'with empty cluster_id' do
      it 'does not subscribe to any stream' do
        initial_streams = subscription.streams.dup
        perform :subscribe_to_cluster, cluster_id: ''
        expect(subscription.streams).to eq(initial_streams)
      end
    end

    context 'with nil cluster_id' do
      it 'does not subscribe to any stream' do
        initial_streams = subscription.streams.dup
        perform :subscribe_to_cluster, cluster_id: nil
        expect(subscription.streams).to eq(initial_streams)
      end
    end
  end
end
