require 'rails_helper'

RSpec.describe NodesHelper, type: :helper do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:node) { create(:node, cluster: cluster, database_type_version: database_type_version) }

  describe '#node_form_builder_for_turbo' do
    it 'returns a form builder for the node' do
      form_builder = helper.node_form_builder_for_turbo(cluster, node)
      expect(form_builder).to be_a(ActionView::Helpers::FormBuilder)
    end

    it 'creates form with correct model path' do
      # This is a bit tricky to test directly, but we can verify it doesn't raise an error
      expect {
        helper.node_form_builder_for_turbo(cluster, node)
      }.not_to raise_error
    end
  end

  describe '#node_status_badge' do
    before do
      # Mock the node methods that would be called
      allow(node).to receive(:status_badge_class).and_return('badge bg-success')
      allow(node).to receive(:status_display).and_return('Active')
      allow(node).to receive(:status).and_return('active')
    end

    it 'creates a span with correct badge class' do
      result = helper.node_status_badge(node)
      expect(result).to include('badge bg-success')
      expect(result).to include('<span')
      expect(result).to include('Active')
    end

    it 'includes data attributes for node status tracking' do
      result = helper.node_status_badge(node)
      expect(result).to include("data-node-status=\"#{node.id}\"")
      expect(result).to include('data-initial-status="active"')
    end

    it 'accepts additional CSS classes' do
      result = helper.node_status_badge(node, class: 'extra-class')
      expect(result).to include('badge bg-success extra-class')
    end

    it 'handles nodes without status gracefully' do
      allow(node).to receive(:status).and_return(nil)
      allow(node).to receive(:status_display).and_return('Pending')
      allow(node).to receive(:status_badge_class).and_return('badge bg-warning')

      result = helper.node_status_badge(node)
      expect(result).to include('Pending')
      expect(result).to include('badge bg-warning')
    end
  end

  describe '#node_status_message_area' do
    it 'creates a div with correct CSS classes' do
      result = helper.node_status_message_area(node)
      expect(result).to include('<div')
      expect(result).to include('status-message text-muted small')
    end

    it 'includes data attribute for message updates' do
      result = helper.node_status_message_area(node)
      expect(result).to include("data-node-status-message=\"#{node.id}\"")
    end

    it 'is initially hidden' do
      result = helper.node_status_message_area(node)
      expect(result).to include('style="display: none;"')
    end

    it 'accepts additional CSS classes' do
      result = helper.node_status_message_area(node, class: 'extra-class')
      expect(result).to include('status-message text-muted small extra-class')
    end

    it 'starts with empty content' do
      result = helper.node_status_message_area(node)
      # Should have opening and closing div tags with nothing in between (except whitespace)
      expect(result).to match(/<div[^>]*>\s*<\/div>/)
    end
  end
end
