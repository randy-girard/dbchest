require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:node) { create(:node, cluster: cluster, database_type_version: database_type_version) }

  describe '#node_status_display' do
    context 'when node has a status' do
      it 'returns humanized status' do
        node.status = 'provisioning'
        expect(helper.node_status_display(node)).to eq('Provisioning')
      end

      it 'handles underscored statuses' do
        node.status = 'waiting_for_replica'
        expect(helper.node_status_display(node)).to eq('Waiting for replica')
      end
    end

    context 'when node has no status' do
      it 'returns "Pending"' do
        node.status = nil
        expect(helper.node_status_display(node)).to eq('Pending')
      end
    end
  end

  describe '#node_status_badge_class' do
    context 'for active/running statuses' do
      it 'returns success badge class' do
        node.status = 'active'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-success')
      end

      it 'handles running status' do
        node.status = 'running'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-success')
      end
    end

    context 'for pending/creating/provisioning statuses' do
      it 'returns warning badge class for pending' do
        node.status = 'pending'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-warning')
      end

      it 'returns warning badge class for creating' do
        node.status = 'creating'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-warning')
      end

      it 'returns warning badge class for provisioning' do
        node.status = 'provisioning'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-warning')
      end
    end

    context 'for destroying/stopping statuses' do
      it 'returns info badge class for destroying' do
        node.status = 'destroying'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-info')
      end

      it 'returns info badge class for stopping' do
        node.status = 'stopping'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-info')
      end
    end

    context 'for error/failed statuses' do
      it 'returns danger badge class for error' do
        node.status = 'error'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-danger')
      end

      it 'returns danger badge class for failed' do
        node.status = 'failed'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-danger')
      end
    end

    context 'for destroyed status' do
      it 'returns dark badge class' do
        node.status = 'destroyed'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-dark')
      end
    end

    context 'for unknown statuses' do
      it 'returns primary badge class' do
        node.status = 'unknown_status'
        expect(helper.node_status_badge_class(node)).to eq('badge bg-primary')
      end
    end

    context 'when node has no status' do
      it 'returns warning badge class (defaults to pending)' do
        node.status = nil
        expect(helper.node_status_badge_class(node)).to eq('badge bg-warning')
      end
    end
  end
end
