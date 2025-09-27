require 'rails_helper'

RSpec.describe TerraformBaseService, type: :service do
  let(:service) { described_class.new }
  let(:database_type) { create(:database_type, slug: 'postgresql') }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider_type) { create(:provider_type, key: 'proxmox') }
  let(:provider) { create(:provider, provider_type: provider_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

  before do
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:cp_r)
    allow(FileUtils).to receive(:rm_rf)
    allow(SecureRandom).to receive(:hex).and_return('abc123')
    allow(Time).to receive(:current).and_return(Time.parse('2023-01-01 12:00:00'))
  end

  describe '#setup_working_directory' do
    it 'creates working directory and returns environment hash' do
      result = service.send(:setup_working_directory, node, 'test')

      expect(FileUtils).to have_received(:mkdir_p).at_least(:once)
      expect(result).to include(:work_dir, :run_id, :terraform_log_path)
      expect(result[:run_id]).to eq('abc123')
    end
  end

  describe '#copy_terraform_templates' do
    let(:work_dir) { '/tmp/test' }

    it 'copies templates for valid provider type' do
      service.send(:copy_terraform_templates, work_dir, provider_type)

      expected_source = Rails.root.join('lib', 'terraform', 'proxmox')
      expect(FileUtils).to have_received(:cp_r).with("#{expected_source}/.", work_dir)
    end

    it 'raises error for invalid provider type' do
      invalid_provider_type = create(:provider_type, key: 'invalid')

      expect {
        service.send(:copy_terraform_templates, work_dir, invalid_provider_type)
      }.to raise_error(ArgumentError, /Invalid provider type/)
    end
  end

  describe '#prepare_terraform_vars' do
    before do
      allow(node).to receive(:ssh_public_key).and_return('ssh-rsa public_key')
      allow(node).to receive(:ssh_private_key).and_return('private_key_content')
      allow(node).to receive(:database_type_slug).and_return('postgresql')
      allow(node).to receive(:database_version).and_return('15')
      allow(node).to receive(:replica?).and_return(false)
      allow(node.provider).to receive(:terraform_vars).and_return({ 'api_url' => 'https://example.com' })
    end

    it 'prepares terraform variables correctly' do
      vars = service.send(:prepare_terraform_vars, node)

      expect(vars).to include(
        api_url: 'https://example.com',
        ssh_public_key: 'ssh-rsa public_key',
        ssh_private_key: 'private_key_content',
        database_type: 'postgresql',
        database_version: '15',
        node_id: node.id.to_s,
        is_replica: false
      )
    end
  end

  describe '#normalize_node_name' do
    it 'normalizes node names correctly' do
      expect(service.send(:normalize_node_name, 'Test Node 123')).to eq('test-node-123')
      expect(service.send(:normalize_node_name, 'node_with_underscores')).to eq('node-with-underscores')
      expect(service.send(:normalize_node_name, '--leading-trailing--')).to eq('leading-trailing')
    end
  end

  describe '#execute_terraform_commands' do
    let(:work_dir) { '/tmp/test' }
    let(:terraform_log_path) { '/tmp/test.log' }
    let(:commands) { [ 'terraform init', 'terraform plan' ] }

    it 'executes all commands in sequence' do
      expect(service).to receive(:run_cmd).with('terraform init', work_dir, terraform_log_path)
      expect(service).to receive(:run_cmd).with('terraform plan', work_dir, terraform_log_path)

      service.send(:execute_terraform_commands, commands, work_dir, terraform_log_path)
    end
  end

  describe '#cleanup_on_success' do
    let(:work_dir) { '/tmp/test' }

    it 'removes working directory' do
      allow(Dir).to receive(:exist?).with(work_dir).and_return(true)

      service.send(:cleanup_on_success, work_dir)

      expect(FileUtils).to have_received(:rm_rf).with(work_dir)
    end
  end

  describe '#preserve_on_failure' do
    let(:work_dir) { '/tmp/test' }
    let(:error) { StandardError.new('Test error') }

    it 'logs error and re-raises' do
      expect(Rails.logger).to receive(:error).twice

      expect {
        service.send(:preserve_on_failure, work_dir, 'test', error)
      }.to raise_error(StandardError, 'Test error')
    end
  end
end
