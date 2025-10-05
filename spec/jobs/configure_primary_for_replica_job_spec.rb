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

    # Mock ActionCable broadcasts to avoid errors
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe '#perform' do
    context 'with valid parameters' do
      let(:mock_ansible_service) { instance_double(AnsiblePlaybookService) }

      before do
        allow(AnsiblePlaybookService).to receive(:new).and_return(mock_ansible_service)
        allow(mock_ansible_service).to receive(:create_temp_workspace)
        allow(mock_ansible_service).to receive(:ensure_temp_workspace_exists)
        allow(mock_ansible_service).to receive(:workspace_path).and_return('/tmp/ansible_workspace')
        allow(mock_ansible_service).to receive(:write_inventory).and_return('/tmp/inventory')
        allow(mock_ansible_service).to receive(:write_vars_file).and_return('/tmp/vars.yml')
        allow(mock_ansible_service).to receive(:cleanup!)

        # Mock File operations for playbook creation
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(Rails.root.join('lib/ansible/postgresql/configure_primary_replication.yml')).and_return('playbook content')
        allow(File).to receive(:write).and_call_original
        allow(File).to receive(:write).with('/tmp/ansible_workspace/configure_primary_replication.yml', anything)

        # Mock Node.find to return our mocked instances
        allow(Node).to receive(:find).with(primary_node.id).and_return(primary_node)
        allow(Node).to receive(:find).with(replica_node.id).and_return(replica_node)

        allow(primary_node).to receive(:ensure_replication_password!).and_return('repl_password_123')
        allow(primary_node).to receive(:ssh_private_key).and_return('fake-ssh-key-content')
        allow(primary_node).to receive(:get_ip_address).and_return('192.168.1.10')

        # Mock successful Ansible execution
        allow(Open3).to receive(:capture3).and_return([ 'Success output', '', double(success?: true) ])

        # Mock file operations
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:delete)

        # Mock Tempfile for SSH key
        ssh_key_tempfile = double('Tempfile')
        allow(Tempfile).to receive(:new).and_return(ssh_key_tempfile)
        allow(ssh_key_tempfile).to receive(:write)
        allow(ssh_key_tempfile).to receive(:chmod)
        allow(ssh_key_tempfile).to receive(:flush)
        allow(ssh_key_tempfile).to receive(:close)
        allow(ssh_key_tempfile).to receive(:unlink)
        allow(ssh_key_tempfile).to receive(:path).and_return('/tmp/ssh_key')
      end

      it 'creates ansible workspace and cleans up' do
        expect(mock_ansible_service).to receive(:create_temp_workspace)
        expect(mock_ansible_service).to receive(:cleanup!)

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: replica_ip
        )
      end

      it 'completes successfully and broadcasts status updates' do
        # Perform the job
        expect {
          job.perform(
            primary_node_id: primary_node.id,
            replica_node_id: replica_node.id,
            replica_ip: replica_ip
          )
        }.not_to raise_error

        # Verify ActionCable broadcasts were made
        expect(ActionCable.server).to have_received(:broadcast).at_least(:once)
      end
    end

    context 'with invalid replica IP' do
      let(:mock_ansible_service) { instance_double(AnsiblePlaybookService) }

      before do
        allow(AnsiblePlaybookService).to receive(:new).and_return(mock_ansible_service)
        allow(mock_ansible_service).to receive(:cleanup!)

        # Mock Node.find to return our instances
        allow(Node).to receive(:find).with(primary_node.id).and_return(primary_node)
        allow(Node).to receive(:find).with(replica_node.id).and_return(replica_node)

        allow(replica_node).to receive(:update_status!)
      end

      it 'fails with blank IP' do
        expect(replica_node).to receive(:update_status!).with('error', 'Primary configuration failed: replica_ip is blank or empty')

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: ''
        )
      end

      it 'fails with invalid IP format' do
        expect(replica_node).to receive(:update_status!).with('error', "Primary configuration failed: replica_ip 'invalid-ip' is not a valid IP address")

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: 'invalid-ip'
        )
      end
    end

    context 'with blank replication password' do
      let(:mock_ansible_service) { instance_double(AnsiblePlaybookService) }

      before do
        allow(AnsiblePlaybookService).to receive(:new).and_return(mock_ansible_service)
        allow(mock_ansible_service).to receive(:create_temp_workspace)
        allow(mock_ansible_service).to receive(:cleanup!)

        # Mock Node.find to return our instances
        allow(Node).to receive(:find).with(primary_node.id).and_return(primary_node)
        allow(Node).to receive(:find).with(replica_node.id).and_return(replica_node)

        allow(primary_node).to receive(:ensure_replication_password!).and_return(nil)
        allow(replica_node).to receive(:update_status!)
      end

      it 'fails when replication password is blank' do
        expect(replica_node).to receive(:update_status!).with('error', 'Primary configuration failed: replication_password is blank or empty after ensure_replication_password!')

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: replica_ip
        )
      end
    end

    context 'when ansible execution fails' do
      let(:mock_ansible_service) { instance_double(AnsiblePlaybookService) }

      before do
        allow(AnsiblePlaybookService).to receive(:new).and_return(mock_ansible_service)
        allow(mock_ansible_service).to receive(:create_temp_workspace)
        allow(mock_ansible_service).to receive(:ensure_temp_workspace_exists)
        allow(mock_ansible_service).to receive(:workspace_path).and_return('/tmp/ansible_workspace')
        allow(mock_ansible_service).to receive(:write_inventory).and_return('/tmp/inventory')
        allow(mock_ansible_service).to receive(:write_vars_file).and_return('/tmp/vars.yml')
        allow(mock_ansible_service).to receive(:cleanup!)

        # Mock File operations for playbook creation
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(Rails.root.join('lib/ansible/postgresql/configure_primary_replication.yml')).and_return('playbook content')
        allow(File).to receive(:write).and_call_original
        allow(File).to receive(:write).with('/tmp/ansible_workspace/configure_primary_replication.yml', anything)

        # Mock Node.find to return our instances
        allow(Node).to receive(:find).with(primary_node.id).and_return(primary_node)
        allow(Node).to receive(:find).with(replica_node.id).and_return(replica_node)

        allow(primary_node).to receive(:ensure_replication_password!).and_return('password')
        allow(primary_node).to receive(:ssh_private_key).and_return('fake-ssh-key-content')
        allow(primary_node).to receive(:get_ip_address).and_return('192.168.1.10')
        allow(replica_node).to receive(:update_status!)

        # Mock log file operations
        log_file = double('File')
        allow(File).to receive(:open).and_call_original
        allow(File).to receive(:open).with(anything, 'a').and_return(log_file)
        allow(log_file).to receive(:puts)
        allow(log_file).to receive(:flush)
        allow(log_file).to receive(:close)
        allow(log_file).to receive(:closed?).and_return(false)

        # Mock failed Ansible execution with popen2e
        wait_thr = double('Process::Waiter')
        allow(wait_thr).to receive(:value).and_return(double(success?: false, exitstatus: 1))

        allow(Open3).to receive(:popen2e).and_yield(
          double('stdin', close: nil),
          [ 'Ansible error' ].each,
          wait_thr
        )

        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:delete)

        # Mock Tempfile for SSH key
        ssh_key_tempfile = double('Tempfile')
        allow(Tempfile).to receive(:new).and_return(ssh_key_tempfile)
        allow(ssh_key_tempfile).to receive(:write)
        allow(ssh_key_tempfile).to receive(:chmod)
        allow(ssh_key_tempfile).to receive(:flush)
        allow(ssh_key_tempfile).to receive(:close)
        allow(ssh_key_tempfile).to receive(:unlink)
        allow(ssh_key_tempfile).to receive(:path).and_return('/tmp/ssh_key')
      end

      it 'updates replica node status on failure' do
        expect(replica_node).to receive(:update_status!).with('error', /Failed to configure primary: Ansible failed with exit code 1/)

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

        # Mock Node.find to return our instances
        allow(Node).to receive(:find).with(primary_node.id).and_return(primary_node)
        allow(Node).to receive(:find).with(replica_node.id).and_return(replica_node)

        allow(replica_node).to receive(:update_status!)
        allow(primary_node).to receive(:ensure_replication_password!).and_raise(StandardError, 'Test error')
      end

      it 'handles exceptions gracefully and cleans up' do
        expect(mock_ansible_service).to receive(:cleanup!)
        expect(replica_node).to receive(:update_status!).with('error', 'Primary configuration job failed: Test error')

        job.perform(
          primary_node_id: primary_node.id,
          replica_node_id: replica_node.id,
          replica_ip: replica_ip
        )
      end
    end
  end
end
