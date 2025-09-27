require 'rails_helper'

RSpec.describe AnsiblePlaybookService, type: :service do
  let(:service) { described_class.new }

  after do
    service.cleanup!
  end

  describe '#create_temp_workspace' do
    it 'creates a temporary directory' do
      workspace_path = service.create_temp_workspace

      expect(workspace_path).to be_present
      expect(Dir.exist?(workspace_path)).to be true
      expect(workspace_path).to include('ansible_playbooks_')
    end

    it 'returns the same path on subsequent calls' do
      path1 = service.create_temp_workspace
      path2 = service.create_temp_workspace

      expect(path1).to eq(path2)
    end
  end

  describe '#write_playbook' do
    let(:playbook_content) do
      <<~YAML
        ---
        - name: Test playbook
          hosts: all
          vars:
            test_var: "{{ test_value }}"
          tasks:
            - name: Echo test
              debug:
                msg: "Hello {{ name }}"
      YAML
    end

    it 'creates a playbook file with processed variables' do
      variables = { 'test_value' => 'processed', 'name' => 'World' }

      playbook_path = service.write_playbook('test_playbook', playbook_content, variables)

      expect(File.exist?(playbook_path)).to be true
      expect(playbook_path).to end_with('test_playbook.yml')

      content = File.read(playbook_path)
      expect(content).to include('test_var: "processed"')
      expect(content).to include('msg: "Hello World"')
    end
  end

  describe '#write_playbook_from_template' do
    let(:template_path) { 'lib/ansible/postgresql/configure_primary_replication.yml' }

    it 'creates a playbook from existing template' do
      variables = {
        'replica_ip' => '192.168.1.100',
        'replica_node_name' => 'test-replica',
        'replication_password' => 'secret123'
      }

      playbook_path = service.write_playbook_from_template(
        template_path,
        'primary_config',
        variables
      )

      expect(File.exist?(playbook_path)).to be true
      expect(playbook_path).to end_with('primary_config.yml')

      content = File.read(playbook_path)
      expect(content).to include('192.168.1.100')
      expect(content).to include('test-replica')
      expect(content).to include('secret123')
    end
  end

  describe '#write_inventory' do
    let(:hosts_config) do
      {
        'postgres_servers' => [
          {
            ip: '192.168.1.10',
            user: 'root',
            ssh_key: '/tmp/key.pem',
            skip_host_check: true
          }
        ],
        'mysql_servers' => [
          {
            ip: '192.168.1.20',
            user: 'ubuntu'
          }
        ]
      }
    end

    it 'creates an inventory file with proper format' do
      inventory_path = service.write_inventory(hosts_config)

      expect(File.exist?(inventory_path)).to be true

      content = File.read(inventory_path)
      expect(content).to include('[postgres_servers]')
      expect(content).to include('192.168.1.10 ansible_user=root')
      expect(content).to include('ansible_ssh_private_key_file=/tmp/key.pem')
      expect(content).to include("ansible_ssh_common_args='-o StrictHostKeyChecking=no'")
      expect(content).to include('[mysql_servers]')
      expect(content).to include('192.168.1.20 ansible_user=ubuntu')
    end
  end

  describe '#write_vars_file' do
    let(:variables) do
      {
        'database_name' => 'test_db',
        'port' => 5432,
        'enabled' => true
      }
    end

    it 'creates a YAML vars file' do
      vars_path = service.write_vars_file(variables)

      expect(File.exist?(vars_path)).to be true
      expect(vars_path).to end_with('vars.yml')

      content = File.read(vars_path)
      parsed = YAML.safe_load(content)

      expect(parsed['database_name']).to eq('test_db')
      expect(parsed['port']).to eq(5432)
      expect(parsed['enabled']).to be true
    end
  end

  describe '#cleanup!' do
    it 'removes all temporary files and directories' do
      workspace_path = service.create_temp_workspace
      playbook_path = service.write_playbook('test', '---\n- hosts: all', {})

      expect(Dir.exist?(workspace_path)).to be true
      expect(File.exist?(playbook_path)).to be true

      service.cleanup!

      expect(Dir.exist?(workspace_path)).to be false
      expect(File.exist?(playbook_path)).to be false
    end

    it 'handles cleanup gracefully when files do not exist' do
      service.create_temp_workspace
      service.cleanup!

      # Should not raise an error when called again
      expect { service.cleanup! }.not_to raise_error
    end
  end

  describe '#workspace_path' do
    it 'returns nil when no workspace is created' do
      expect(service.workspace_path).to be_nil
    end

    it 'returns the workspace path after creation' do
      workspace_path = service.create_temp_workspace
      expect(service.workspace_path).to eq(workspace_path)
    end
  end
end
