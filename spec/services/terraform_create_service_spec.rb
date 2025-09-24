require 'rails_helper'

RSpec.describe TerraformCreateService, type: :service do
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
    allow(CloudInitService).to receive(:new).and_return(double('cloud_init_service', write_script_to_file: '/tmp/script.sh'))
    allow(Open3).to receive(:capture2).and_return([ '{"ip": "192.168.1.100"}', double('status', success?: true) ])

    # Mock node methods
    allow(node).to receive(:ensure_ssh_keys!)
    allow(node).to receive(:ensure_root_password!)
    allow(node).to receive(:ssh_public_key).and_return('ssh-rsa AAAAB3...')
    allow(node).to receive(:ssh_private_key).and_return('-----BEGIN PRIVATE KEY-----...')
    allow(node).to receive(:root_password).and_return('password123')
    allow(node).to receive(:database_type_slug).and_return('postgresql')
    allow(node).to receive(:database_version).and_return('15')
    allow(node).to receive(:replica?).and_return(false)
    allow(node).to receive(:parent_node).and_return(nil)
    allow(node).to receive(:node_settings).and_return([])
    allow(node).to receive(:runtime_config=)
    allow(node).to receive(:save)

    # Mock provider methods
    allow(provider).to receive(:terraform_vars).and_return({ 'api_url' => 'https://proxmox.example.com' })

    # Mock service methods
    allow(service).to receive(:command).and_return('/usr/bin/terraform')
    allow(service).to receive(:run_cmd)
    allow(service).to receive(:load_state_from_db)
    allow(service).to receive(:save_state_to_db)
    allow(service).to receive(:terraform_log_file_path).and_return('/tmp/terraform.log')
    allow(service).to receive(:vars_to_tfvars).and_return('name = "test"')
  end

  describe '#perform' do
    context 'with valid node' do
      it 'validates provider type' do
        invalid_provider_type = create(:provider_type, key: 'invalid')
        invalid_provider = create(:provider, provider_type: invalid_provider_type)
        invalid_node = create(:node, cluster: cluster, database_type_version: database_type_version, provider: invalid_provider)

        expect {
          service.perform(invalid_node.id)
        }.to raise_error(ArgumentError, 'Invalid provider type')
      end

      it 'creates working directory' do
        expect(FileUtils).to receive(:mkdir_p).with(kind_of(Pathname))
        service.perform(node.id)
      end

      it 'copies terraform templates' do
        expect(FileUtils).to receive(:cp_r).with(kind_of(String), kind_of(Pathname))
        service.perform(node.id)
      end

      it 'generates cloud-init script' do
        cloud_init_service = double('cloud_init_service')
        expect(CloudInitService).to receive(:new).and_return(cloud_init_service)
        expect(cloud_init_service).to receive(:write_script_to_file).with(node.id, kind_of(Pathname), false)

        service.perform(node.id)
      end

      it 'writes terraform variables file' do
        expect(File).to receive(:write).with(kind_of(Pathname), kind_of(String))
        service.perform(node.id)
      end

      it 'runs terraform commands in sequence' do
        expect(service).to receive(:run_cmd).with(/terraform init/, kind_of(Pathname), kind_of(String))
        expect(service).to receive(:run_cmd).with(/terraform plan/, kind_of(Pathname), kind_of(String))
        expect(service).to receive(:run_cmd).with(/terraform apply/, kind_of(Pathname), kind_of(String))

        service.perform(node.id)
      end

      it 'captures terraform outputs' do
        expect(Open3).to receive(:capture2).with('/usr/bin/terraform', 'output', '-json', chdir: kind_of(Pathname))
        service.perform(node.id)
      end

      it 'completes successfully' do
        expect { service.perform(node.id) }.not_to raise_error
      end
    end

    context 'with replica node' do
      let(:primary_node) { create(:node, cluster: cluster, database_type_version: database_type_version, provider: provider) }
      let(:replica_node) { create(:node, cluster: cluster, database_type_version: database_type_version, provider: provider, parent_node: primary_node) }

      before do
        allow(replica_node).to receive(:ensure_ssh_keys!)
        allow(replica_node).to receive(:ensure_root_password!)
        allow(replica_node).to receive(:ssh_public_key).and_return('ssh-rsa AAAAB3...')
        allow(replica_node).to receive(:ssh_private_key).and_return('-----BEGIN PRIVATE KEY-----...')
        allow(replica_node).to receive(:root_password).and_return('password123')
        allow(replica_node).to receive(:database_type_slug).and_return('postgresql')
        allow(replica_node).to receive(:database_version).and_return('15')
        allow(replica_node).to receive(:replica?).and_return(true)
        allow(replica_node).to receive(:parent_node).and_return(primary_node)
        allow(replica_node).to receive(:node_settings).and_return([])
        allow(replica_node).to receive(:runtime_config=)
        allow(replica_node).to receive(:save)
        allow(primary_node).to receive(:get_ip_address).and_return('192.168.1.100')
      end

      it 'generates replica cloud-init script' do
        cloud_init_service = double('cloud_init_service')
        expect(CloudInitService).to receive(:new).and_return(cloud_init_service)
        expect(cloud_init_service).to receive(:write_script_to_file).with(replica_node.id, kind_of(Pathname), true)

        service.perform(replica_node.id)
      end

      it 'completes successfully for replica' do
        expect { service.perform(replica_node.id) }.not_to raise_error
      end
    end

    context 'with node settings' do
      let(:node_setting) { create(:node_setting, node: node, key: 'subnet', value: 'subnet-123') }

      before do
        allow(node).to receive(:node_settings).and_return([ node_setting ])
      end

      it 'completes successfully with node settings' do
        expect { service.perform(node.id) }.not_to raise_error
      end
    end

    context 'when terraform command fails' do
      before do
        allow(service).to receive(:run_cmd).and_raise('Terraform command failed')
      end

      it 'preserves working directory for debugging' do
        expect(FileUtils).not_to receive(:rm_rf)
        expect { service.perform(node.id) }.to raise_error('Terraform command failed')
      end

      it 'logs error message' do
        expect(Rails.logger).to receive(:error).with(/Terraform deployment failed/)
        expect(Rails.logger).to receive(:error).with(/Error:/)

        expect { service.perform(node.id) }.to raise_error('Terraform command failed')
      end
    end

    context 'with nonexistent node' do
      it 'handles missing node gracefully' do
        expect { service.perform(999999) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
