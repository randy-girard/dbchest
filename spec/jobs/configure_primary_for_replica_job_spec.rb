require 'rails_helper'

RSpec.describe ConfigurePrimaryForReplicaJob, type: :job do
  let(:database_type) { create(:database_type, slug: 'postgresql') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '15.0') }
  let(:cluster) { create(:cluster, database_type: database_type) }
  
  let(:primary_node) do
    create(:node, 
           cluster: cluster,
           database_type_version: database_type_version,
           runtime_config: { 'ip_address' => '192.168.1.10' },
           ssh_private_key: 'fake-ssh-key',
           replication_password: 'repl_password_123')
  end
  
  let(:replica_node) do
    create(:node,
           cluster: cluster,
           database_type_version: database_type_version,
           parent_node: primary_node,
           runtime_config: { 'ip_address' => '192.168.1.20' })
  end
  
  let(:replica_ip) { '192.168.1.20' }
  
  let(:job) { described_class.new }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:debug)
  end

  describe '#perform' do
    context 'with valid parameters' do
      let(:mock_ansible_service) { instance_double(AnsiblePlaybookService) }
      let(:temp_workspace) { '/tmp/ansible_test_workspace' }
      let(:playbook_path) { '/tmp/ansible_test_workspace/configure_primary_replication.yml' }
      let(:inventory_path) { '/tmp/ansible_test_workspace/inventory' }

      before do
        allow(AnsiblePlaybookService).to receive(:new).and_return(mock_ansible_service)
        allow(mock_ansible_service).to receive(:create_temp_workspace).and_return(temp_workspace)
        allow(mock_ansible_service).to receive(:write_playbook_from_template).and_return(playbook_path)
        allow(mock_ansible_service).to receive(:write_inventory).and_return(inventory_path)
        allow(mock_ansible_service).to receive(:cleanup!)
        
        allow(primary_node).to receive(:ensure_replication_password!).and_return('repl_password_123')
        allow(primary_node).to receive(:ssh_private_key_path).and_return('/tmp/ssh_key')
        
        # Mock successful Ansible execution
        allow(Open3).to receive(:capture3).and_return(['Success output', '', double(success?: true)])
        
        # Mock file cleanup
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:delete)
      end

      it 'creates temporary workspace and executes ansible playbook successfully' do
        expect(mock_ansible_service).to receive(:create_temp_workspace)
        expect(mock_ansible_service).to receive(:write_playbook_from_template).with(
          'lib/ansible/postgresql/configure_primary_replication.yml',
          'configure_primary_replication',
          hash_including(
            'replica_ip' => replica_ip,
            'replica_node_name' => replica_node.name,
            'replication_password' => 'repl_password_123'
          )
        )
        expect(mock_ansible_service).to receive(:write_inventory)
        expect(mock_ansible_service).to receive(:cleanup!)

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: replica_ip
        )
      end

      it 'updates replica node status on success' do
        expect(replica_node).to receive(:update_status!).with('active', 'Primary configured for replication')

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: replica_ip
        )
      end
    end

    context 'with invalid replica IP' do
      it 'fails with blank IP' do
        expect(replica_node).to receive(:update_status!).with('error', /Primary configuration failed.*blank/)

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: ''
        )
      end

      it 'fails with invalid IP format' do
        expect(replica_node).to receive(:update_status!).with('error', /Primary configuration failed.*not a valid IP/)

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: 'invalid-ip'
        )
      end
    end

    context 'when ansible execution fails' do
      let(:mock_ansible_service) { instance_double(AnsiblePlaybookService) }

      before do
        allow(AnsiblePlaybookService).to receive(:new).and_return(mock_ansible_service)
        allow(mock_ansible_service).to receive(:create_temp_workspace)
        allow(mock_ansible_service).to receive(:write_playbook_from_template).and_return('/tmp/playbook.yml')
        allow(mock_ansible_service).to receive(:write_inventory).and_return('/tmp/inventory')
        allow(mock_ansible_service).to receive(:cleanup!)
        
        allow(primary_node).to receive(:ensure_replication_password!).and_return('password')
        allow(primary_node).to receive(:ssh_private_key_path).and_return('/tmp/key')
        
        # Mock failed Ansible execution
        allow(Open3).to receive(:capture3).and_return(['', 'Ansible error', double(success?: false)])
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:delete)
      end

      it 'updates replica node status on failure' do
        expect(replica_node).to receive(:update_status!).with('error', /Failed to configure primary.*Ansible error/)

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: replica_ip
        )
      end

      it 'cleans up ansible workspace on failure' do
        expect(mock_ansible_service).to receive(:cleanup!)

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: replica_ip
        )
      end
    end

    context 'when an exception occurs' do
      let(:mock_ansible_service) { instance_double(AnsiblePlaybookService) }

      before do
        allow(AnsiblePlaybookService).to receive(:new).and_return(mock_ansible_service)
        allow(mock_ansible_service).to receive(:create_temp_workspace)
        allow(mock_ansible_service).to receive(:cleanup!)
        
        allow(primary_node).to receive(:ensure_replication_password!).and_raise(StandardError, 'Test error')
      end

      it 'handles exceptions gracefully and cleans up' do
        expect(mock_ansible_service).to receive(:cleanup!)
        expect(replica_node).to receive(:update_status!).with('error', /Primary configuration job failed.*Test error/)

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: replica_ip
        )
      end
    end
  end
end
