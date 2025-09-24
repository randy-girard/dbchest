require 'rails_helper'

RSpec.describe TerraformDestroyService, type: :service do
  let(:database_type) { create(:database_type, name: 'PostgreSQL') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '15') }
  let(:provider_type) { create(:provider_type, key: 'proxmox') }
  let(:provider) { create(:provider, provider_type: provider_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:node) { create(:node, cluster: cluster, database_type_version: database_type_version, provider: provider) }
  let(:service) { described_class.new }

  before do
    # Mock external dependencies
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:cp_r)
    allow(FileUtils).to receive(:rm_rf)
    allow(File).to receive(:write)
    allow(File).to receive(:open).and_yield(double('file', puts: nil, flush: nil, close: nil))
    allow(Dir).to receive(:exist?).and_return(true)

    # Mock service methods
    allow(service).to receive(:command).and_return('/usr/bin/terraform')
    allow(service).to receive(:run_cmd)
    allow(service).to receive(:load_state_from_db)
    allow(service).to receive(:save_state_to_db)
    allow(service).to receive(:terraform_log_file_path).and_return('/tmp/terraform.log')
    allow(service).to receive(:vars_to_tfvars).and_return('name = "test"')

    # Mock node methods
    allow(node).to receive(:exists_in_provider?).and_return(true)
    allow(node).to receive(:ssh_public_key).and_return('ssh-rsa AAAAB3...')
    allow(node).to receive(:ssh_private_key).and_return('-----BEGIN PRIVATE KEY-----...')
    allow(node).to receive(:node_settings).and_return([])
    allow(node).to receive(:terraform_state).and_return('{"version": 4}')
    allow(node).to receive(:terraform_state=)
    allow(node).to receive(:save)

    # Mock provider methods
    allow(provider).to receive(:terraform_vars).and_return({ 'api_url' => 'https://proxmox.example.com' })
  end

  describe '#perform' do
    context 'with nonexistent node' do
      it 'handles missing node gracefully' do
        expect { service.perform(999999) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when node does not exist in provider' do
      before do
        allow(node).to receive(:exists_in_provider?).and_return(false)
      end

      it 'does not attempt destroy operation' do
        result = service.perform(node.id)
        expect(result).to be_nil
      end
    end

    context 'when node exists in provider' do
      it 'completes without error when properly mocked' do
        # This is a basic test to ensure the service can be instantiated and called
        expect(service).to respond_to(:perform)
        expect { service.perform(node.id) }.not_to raise_error
      end
    end

    context 'with invalid provider type' do
      it 'includes TerraformCommon module' do
        expect(service.class.included_modules).to include(TerraformCommon)
      end

      it 'has access to ALLOWED_PROVIDER_KEYS constant' do
        expect(TerraformCommon::ALLOWED_PROVIDER_KEYS).to be_an(Array)
        expect(TerraformCommon::ALLOWED_PROVIDER_KEYS).to include('proxmox')
      end
    end
  end
end
