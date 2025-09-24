require 'rails_helper'

RSpec.describe ProviderClient::Proxmox, type: :model do
  let(:settings) do
    double('settings',
           api_url: 'https://proxmox.example.com:8006/api2/json',
           username: 'test@pam',
           password: 'password')
  end
  let(:client) { described_class.new(settings) }
  let(:mock_proxmox_client) { double('proxmox_client') }

  before do
    allow(ProxmoxAPI).to receive(:new).and_return(mock_proxmox_client)
  end

  describe '#exists?' do
    let(:database_type) { create(:database_type) }
    let(:database_type_version) { create(:database_type_version, database_type: database_type) }
    let(:cluster) { create(:cluster, database_type: database_type) }
    let(:node) { create(:node, cluster: cluster, database_type_version: database_type_version) }
    let(:mock_nodes) { double('nodes') }
    let(:mock_lxc) { double('lxc') }
    let(:mock_status) { double('status') }
    let(:mock_current) { double('current') }

    before do
      allow(node).to receive(:get_runtime_config_value).with('node').and_return('pve')
      allow(node).to receive(:get_runtime_config_value).with('vmid').and_return('100')
      allow(mock_proxmox_client).to receive(:nodes).and_return(mock_nodes)
      allow(mock_nodes).to receive(:[]).with('pve').and_return(mock_nodes)
      allow(mock_nodes).to receive(:lxc).and_return(mock_lxc)
      allow(mock_lxc).to receive(:[]).with('100').and_return(mock_lxc)
      allow(mock_lxc).to receive(:status).and_return(mock_status)
      allow(mock_status).to receive(:current).and_return(mock_current)
    end

    context 'when container exists' do
      it 'returns true' do
        allow(mock_current).to receive(:get).and_return({ status: 'running' })
        expect(client.exists?(node)).to be true
      end
    end

    context 'when container does not exist' do
      it 'returns false' do
        allow(mock_current).to receive(:get).and_raise(StandardError.new('Not found'))
        expect(client.exists?(node)).to be false
      end
    end
  end

  describe '#nodes' do
    let(:mock_nodes) { double('nodes') }

    before do
      allow(mock_proxmox_client).to receive(:nodes).and_return(mock_nodes)
    end

    it 'returns formatted node list' do
      node_data = [
        { node: 'pve1' },
        { node: 'pve2' }
      ]
      allow(mock_nodes).to receive(:get).and_return(node_data)

      result = client.nodes({})
      expect(result).to eq([
                             { 'id' => 'pve1', 'name' => 'pve1' },
                             { 'id' => 'pve2', 'name' => 'pve2' }
                           ])
    end
  end

  describe '#storage' do
    let(:mock_nodes) { double('nodes') }
    let(:mock_storage) { double('storage') }

    before do
      allow(mock_proxmox_client).to receive(:nodes).and_return(mock_nodes)
      allow(mock_nodes).to receive(:[]).with('pve').and_return(mock_nodes)
      allow(mock_nodes).to receive(:storage).and_return(mock_storage)
    end

    it 'returns formatted storage list excluding dir type' do
      storage_data = [
        { storage: 'local-lvm', type: 'lvm', avail: 1073741824, total: 2147483648 },
        { storage: 'local', type: 'dir', avail: 536870912, total: 1073741824 }
      ]
      allow(mock_storage).to receive(:get).and_return(storage_data)

      result = client.storage({ node: 'pve' })
      expect(result.length).to eq(1)
      expect(result.first['id']).to eq('local-lvm')
      expect(result.first['name']).to include('local-lvm')
    end
  end

  describe '#template_storage' do
    let(:mock_nodes) { double('nodes') }
    let(:mock_storage) { double('storage') }

    before do
      allow(mock_proxmox_client).to receive(:nodes).and_return(mock_nodes)
      allow(mock_nodes).to receive(:[]).with('pve').and_return(mock_nodes)
      allow(mock_nodes).to receive(:storage).and_return(mock_storage)
    end

    it 'returns formatted storage list for dir type only' do
      storage_data = [
        { storage: 'local-lvm', type: 'lvm', avail: 1073741824, total: 2147483648 },
        { storage: 'local', type: 'dir', avail: 536870912, total: 1073741824 }
      ]
      allow(mock_storage).to receive(:get).and_return(storage_data)

      result = client.template_storage({ node: 'pve' })
      expect(result.length).to eq(1)
      expect(result.first['id']).to eq('local')
      expect(result.first['name']).to include('local')
    end
  end

  describe '#template_template' do
    let(:mock_nodes) { double('nodes') }
    let(:mock_storage) { double('storage') }
    let(:mock_content) { double('content') }

    before do
      allow(mock_proxmox_client).to receive(:nodes).and_return(mock_nodes)
      allow(mock_nodes).to receive(:[]).with('pve').and_return(mock_nodes)
      allow(mock_nodes).to receive(:storage).and_return(mock_storage)
      allow(mock_storage).to receive(:[]).with('local').and_return(mock_storage)
      allow(mock_storage).to receive(:content).and_return(mock_content)
    end

    it 'returns formatted template list' do
      content_data = [
        { volid: 'local:vztmpl/ubuntu-20.04.tar.gz', content: 'vztmpl' },
        { volid: 'local:iso/ubuntu.iso', content: 'iso' }
      ]
      allow(mock_content).to receive(:get).and_return(content_data)

      result = client.template_template({ node: 'pve', storage: 'local' })
      expect(result.length).to eq(1)
      expect(result.first['id']).to eq('local:vztmpl/ubuntu-20.04.tar.gz')
      expect(result.first['name']).to eq('local:vztmpl/ubuntu-20.04.tar.gz')
    end
  end
end
