require 'rails_helper'

RSpec.describe AnsibleRunService, type: :service do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:service) { AnsibleRunService.new }
  let(:database_type_handler) { double('database_type_handler') }

  before do
    allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
    allow(node).to receive(:database_type_handler).and_return(database_type_handler)
    allow(node).to receive(:database_type_slug).and_return('postgresql')
    allow(node).to receive(:get_runtime_config_value).with("ip_address").and_return('192.168.1.100')
    allow(node).to receive(:ssh_private_key).and_return('fake_ssh_key')
    
    # Mock external dependencies
    allow(service).to receive(:`).with('which ansible-playbook').and_return('/usr/bin/ansible-playbook')
    allow(Open3).to receive(:popen2e).and_yield(double(close: nil), [], double(value: double(exitstatus: 0)))
    allow(Tempfile).to receive(:new).and_return(double(write: nil, flush: nil, path: '/tmp/test', close: nil, unlink: nil, chmod: nil))
    allow(IPAddr).to receive(:new).with('192.168.1.100').and_return(double(to_s: '192.168.1.100'))
  end

  describe '#ansible_path' do
    it 'returns the correct ansible path' do
      expected_path = Rails.root.join("lib", "ansible")
      expect(service.ansible_path).to eq(expected_path)
    end
  end

  describe '#playbook_path' do
    let(:playbook) { 'test_playbook.yml' }

    context 'with database type handler' do
      it 'returns path based on database type slug' do
        expected_path = Rails.root.join("lib", "ansible", "postgresql", playbook).to_s
        expect(service.playbook_path(node, playbook)).to eq(expected_path)
      end
    end

    context 'without database type handler' do
      before do
        allow(node).to receive(:database_type_handler).and_return(nil)
      end

      it 'defaults to postgresql path' do
        expected_path = Rails.root.join("lib", "ansible", "postgresql", playbook).to_s
        expect(service.playbook_path(node, playbook)).to eq(expected_path)
      end
    end
  end

  describe '#perform' do
    let(:playbook) { 'test_playbook.yml' }
    let(:vars) { { 'test_var' => 'test_value' } }
    let(:inventory_file) { double('inventory_file', write: nil, flush: nil, path: '/tmp/inventory', close: nil, unlink: nil) }
    let(:vars_file) { double('vars_file', write: nil, flush: nil, path: '/tmp/vars', close: nil, unlink: nil) }
    let(:key_file) { double('key_file', write: nil, flush: nil, path: '/tmp/key', close: nil, unlink: nil, chmod: nil) }

    before do
      allow(Tempfile).to receive(:new).with("ansible_inventory").and_return(inventory_file)
      allow(Tempfile).to receive(:new).with("ansible_vars").and_return(vars_file)
      allow(Tempfile).to receive(:new).with("ansible_key").and_return(key_file)
    end

    context 'with valid node and IP address' do
      it 'finds the node by id' do
        expect(Node).to receive(:find_by_id).with(node.id)
        service.perform(node.id, playbook)
      end

      it 'gets the IP address from runtime config' do
        expect(node).to receive(:get_runtime_config_value).with("ip_address")
        service.perform(node.id, playbook)
      end

      it 'creates inventory file with correct format' do
        expect(inventory_file).to receive(:write).with("[postgres_servers]\n")
        expect(inventory_file).to receive(:write).with("192.168.1.100 ansible_user=root\n")
        service.perform(node.id, playbook)
      end

      it 'creates SSH key file with correct permissions' do
        expect(key_file).to receive(:write).with('fake_ssh_key')
        expect(key_file).to receive(:chmod).with(0600)
        service.perform(node.id, playbook)
      end

      it 'executes ansible-playbook with correct arguments' do
        expected_cmd = [
          '/usr/bin/ansible-playbook',
          '-i', '/tmp/inventory',
          '--private-key', '/tmp/key',
          Rails.root.join("lib", "ansible", "postgresql", playbook).to_s
        ]
        
        expect(Open3).to receive(:popen2e).with({}, *expected_cmd, chdir: service.ansible_path.to_s)
        service.perform(node.id, playbook)
      end

      context 'with variables' do
        it 'creates vars file and includes it in command' do
          expect(vars_file).to receive(:write).with("test_var: test_value\n")
          
          expected_cmd = [
            '/usr/bin/ansible-playbook',
            '-i', '/tmp/inventory',
            '-e', '@/tmp/vars',
            '--private-key', '/tmp/key',
            Rails.root.join("lib", "ansible", "postgresql", playbook).to_s
          ]
          
          expect(Open3).to receive(:popen2e).with({}, *expected_cmd, chdir: service.ansible_path.to_s)
          service.perform(node.id, playbook, vars: vars)
        end
      end

      it 'cleans up temporary files' do
        expect(inventory_file).to receive(:close)
        expect(inventory_file).to receive(:unlink)
        expect(key_file).to receive(:close)
        expect(key_file).to receive(:unlink)
        
        service.perform(node.id, playbook)
      end
    end

    context 'with invalid IP address' do
      before do
        allow(node).to receive(:get_runtime_config_value).with("ip_address").and_return(nil)
      end

      it 'returns early without executing ansible' do
        expect(Open3).not_to receive(:popen2e)
        service.perform(node.id, playbook)
      end
    end

    context 'with non-existent node' do
      before do
        allow(Node).to receive(:find_by_id).with(999999).and_return(nil)
      end

      it 'handles missing node gracefully' do
        expect { service.perform(999999, playbook) }.not_to raise_error
      end
    end
  end

  describe '#parse_line' do
    before do
      service.instance_variable_set(:@node_id, node.id)
      service.instance_variable_set(:@playbook_name, 'test_playbook.yml')
      allow(service).to receive(:broadcast)
    end

    context 'with task start line' do
      let(:task_line) { 'TASK [Install PostgreSQL] ************************************' }

      it 'creates a new current task' do
        service.parse_line(task_line)
        current_task = service.instance_variable_get(:@current_task)
        
        expect(current_task[:name]).to eq('Install PostgreSQL')
        expect(current_task[:status]).to eq('running')
        expect(current_task[:details]).to eq('')
      end

      it 'broadcasts the new task' do
        expect(service).to receive(:broadcast).with(hash_including(name: 'Install PostgreSQL', status: 'running'))
        service.parse_line(task_line)
      end
    end

    context 'with task result lines' do
      before do
        service.instance_variable_set(:@current_task, { name: 'Test Task', status: 'running', details: '' })
      end

      it 'updates status to success for ok line' do
        service.parse_line('ok: [node-1]')
        current_task = service.instance_variable_get(:@current_task)
        expect(current_task[:status]).to eq('success')
      end

      it 'updates status to changed for changed line' do
        service.parse_line('changed: [node-1]')
        current_task = service.instance_variable_get(:@current_task)
        expect(current_task[:status]).to eq('changed')
      end

      it 'updates status to failed for failed line' do
        service.parse_line('failed: [node-1]')
        current_task = service.instance_variable_get(:@current_task)
        expect(current_task[:status]).to eq('failed')
      end

      it 'appends output to details' do
        service.parse_line('Some output line')
        current_task = service.instance_variable_get(:@current_task)
        expect(current_task[:details]).to include('Some output line')
      end
    end
  end

  describe '#broadcast' do
    let(:task) { { name: 'Test Task', status: 'running', details: 'Some details' } }

    before do
      service.instance_variable_set(:@node_id, node.id)
      service.instance_variable_set(:@playbook_name, 'test_playbook.yml')
      allow(ActionCable.server).to receive(:broadcast)
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(service).to receive(:puts)
    end

    it 'broadcasts to ansible channel' do
      expect(ActionCable.server).to receive(:broadcast).with("ansible", task.to_json)
      service.broadcast(task)
    end

    it 'outputs to console' do
      expect(service).to receive(:puts).with(task.to_json)
      service.broadcast(task)
    end

    context 'in development environment' do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
        allow(Time.current).to receive(:strftime).with("%H:%M:%S").and_return("14:30:00")
      end

      it 'also broadcasts to development console channel' do
        allow(ActionCable.server).to receive(:broadcast)
        expect(ActionCable.server).to receive(:broadcast).with("development_console", hash_including(
          event_type: 'ansible_task',
          node_id: node.id,
          task_name: task["name"],
          status: task["status"],
          details: task["details"],
          playbook: 'test_playbook.yml'
        ))
        service.broadcast(task)
      end
    end
  end
end
