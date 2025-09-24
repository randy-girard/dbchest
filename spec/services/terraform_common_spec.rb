require 'rails_helper'

RSpec.describe TerraformCommon, type: :service do
  let(:test_class) do
    Class.new do
      include TerraformCommon

      def initialize
        # Test class implementation
      end
    end
  end
  let(:service) { test_class.new }

  describe '#vars_to_tfvars' do
    it 'converts simple string variables' do
      vars = { name: 'test-node', port: '5432' }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include('name = "test-node"')
      expect(result).to include('port = "5432"')
    end

    it 'escapes quotes in string values' do
      vars = { description: 'A "quoted" string' }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include('description = "A \\"quoted\\" string"')
    end

    it 'escapes backslashes in string values' do
      vars = { path: 'C:\\Windows\\System32' }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include('path = "C:\\Windows\\System32"')
    end

    it 'escapes newlines in string values' do
      vars = { multiline: "line1\nline2\r\nline3" }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include('multiline = "line1\\nline2\\r\\nline3"')
    end

    it 'handles cloud_init_user_data as base64' do
      base64_data = Base64.encode64('test data').strip
      vars = { cloud_init_user_data: base64_data }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include("cloud_init_user_data = \"#{base64_data}\"")
    end

    it 'handles cloud_init_script as file path' do
      vars = { cloud_init_script: '/path/to/script.sh' }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include('cloud_init_script = "/path/to/script.sh"')
    end

    it 'handles SSH private key with heredoc syntax' do
      private_key = "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC\n-----END PRIVATE KEY-----"
      vars = { ssh_private_key: private_key }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include("ssh_private_key = <<-EOT\n#{private_key}\nEOT")
    end

    it 'handles SSH public key with heredoc syntax' do
      public_key = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@host'
      vars = { ssh_public_key: public_key }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include("ssh_public_key = <<-EOT\n#{public_key}\nEOT")
    end

    it 'joins multiple variables with newlines' do
      vars = { var1: 'value1', var2: 'value2' }
      result = service.send(:vars_to_tfvars, vars)
      expect(result).to include("var1 = \"value1\"\nvar2 = \"value2\"")
    end
  end

  describe '#terraform_log_file_path' do
    it 'creates log directory and returns file path' do
      node_id = 123
      run_id = 'abc123'

      allow(FileUtils).to receive(:mkdir_p)
      allow(Time).to receive(:current).and_return(Time.parse('2023-01-01 12:00:00'))

      result = service.send(:terraform_log_file_path, node_id, run_id)

      expect(FileUtils).to have_received(:mkdir_p).with(Rails.root.join('log', 'terraform'))
      expect(result.to_s).to include('node_123_abc123_20230101_120000.log')
    end
  end

  describe '#broadcast_log' do
    it 'broadcasts to terraform_logs_channel' do
      expect(ActionCable.server).to receive(:broadcast).with('terraform_logs_channel', { message: 'test message' })
      service.send(:broadcast_log, 'test message')
    end

    context 'in development environment' do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
      end

      it 'also broadcasts to development_console' do
        allow(Time).to receive(:current).and_return(Time.parse('2023-01-01 12:00:00'))

        expect(ActionCable.server).to receive(:broadcast).with('terraform_logs_channel', { message: 'test message' })
        expect(ActionCable.server).to receive(:broadcast).with('development_console', {
          timestamp: '12:00:00',
          event_type: 'terraform_log',
          message: 'test message'
        })

        service.send(:broadcast_log, 'test message')
      end
    end
  end

  describe '#load_state_from_db' do
    let(:work_dir) { '/tmp/terraform' }
    let(:record) { double('record', terraform_state: '{"version": 4}') }

    it 'writes terraform state to file when present' do
      expect(File).to receive(:write).with(File.join(work_dir, 'terraform.tfstate'), '{"version": 4}')
      service.send(:load_state_from_db, work_dir, record)
    end

    it 'does nothing when terraform_state is blank' do
      record = double('record', terraform_state: nil)
      expect(File).not_to receive(:write)
      service.send(:load_state_from_db, work_dir, record)
    end

    it 'does nothing when record is nil' do
      expect(File).not_to receive(:write)
      service.send(:load_state_from_db, work_dir, nil)
    end
  end

  describe '#save_state_to_db' do
    let(:work_dir) { '/tmp/terraform' }
    let(:record) { double('record') }
    let(:state_content) { '{"version": 4, "terraform_version": "1.0.0"}' }

    it 'reads terraform state and saves to record' do
      expect(File).to receive(:read).with(File.join(work_dir, 'terraform.tfstate')).and_return(state_content)
      expect(record).to receive(:terraform_state=).with(state_content)
      expect(record).to receive(:save!)

      service.send(:save_state_to_db, work_dir, record)
    end
  end

  describe 'ALLOWED_PROVIDER_KEYS' do
    it 'includes expected provider keys' do
      expect(TerraformCommon::ALLOWED_PROVIDER_KEYS).to include('aws', 'linode', 'proxmox', 'gcp', 'azure')
    end
  end
end
