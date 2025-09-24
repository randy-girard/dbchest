require 'rails_helper'

RSpec.describe CloudInitService, type: :service do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:service) { CloudInitService.new }
  let(:database_type_handler) { double('database_type_handler') }

  before do
    allow(Node).to receive(:find).with(node.id).and_return(node)
    allow(node).to receive(:database_type_handler).and_return(database_type_handler)
  end

  describe '#generate_user_data' do
    context 'with valid node and database type handler' do
      let(:expected_script) { "#!/bin/bash\necho 'Setting up PostgreSQL...'" }

      before do
        allow(database_type_handler).to receive(:generate_cloud_init_script).and_return(expected_script)
      end

      it 'finds the node by id' do
        expect(Node).to receive(:find).with(node.id)
        service.generate_user_data(node.id)
      end

      it 'gets the database type handler from the node' do
        expect(node).to receive(:database_type_handler)
        service.generate_user_data(node.id)
      end

      it 'calls generate_cloud_init_script on the handler for primary node' do
        expect(database_type_handler).to receive(:generate_cloud_init_script).with(node, is_replica: false)
        service.generate_user_data(node.id)
      end

      it 'calls generate_cloud_init_script on the handler for replica node' do
        expect(database_type_handler).to receive(:generate_cloud_init_script).with(node, is_replica: true)
        service.generate_user_data(node.id, true)
      end

      it 'returns the generated script' do
        result = service.generate_user_data(node.id)
        expect(result).to eq(expected_script)
      end
    end

    context 'without database type handler' do
      before do
        allow(node).to receive(:database_type_handler).and_return(nil)
      end

      it 'returns empty string when no handler is available' do
        result = service.generate_user_data(node.id)
        expect(result).to eq("")
      end
    end
  end

  describe '#write_script_to_file' do
    let(:work_dir) { '/tmp/test_work_dir' }
    let(:script_content) { "#!/bin/bash\necho 'Test script'" }
    let(:expected_file_path) { File.join(work_dir, "cloud_init_script.sh") }

    before do
      allow(service).to receive(:generate_user_data).and_return(script_content)
      allow(File).to receive(:write)
      allow(File).to receive(:join).with(work_dir, "cloud_init_script.sh").and_return(expected_file_path)
    end

    it 'generates user data for the node' do
      expect(service).to receive(:generate_user_data).with(node.id, false)
      service.write_script_to_file(node.id, work_dir)
    end

    it 'generates user data for replica when specified' do
      expect(service).to receive(:generate_user_data).with(node.id, true)
      service.write_script_to_file(node.id, work_dir, true)
    end

    it 'writes the script content to the correct file path' do
      expect(File).to receive(:write).with(expected_file_path, script_content)
      service.write_script_to_file(node.id, work_dir)
    end

    it 'returns the script file path' do
      result = service.write_script_to_file(node.id, work_dir)
      expect(result).to eq(expected_file_path)
    end

    context 'with different work directory' do
      let(:custom_work_dir) { '/custom/path' }
      let(:custom_file_path) { File.join(custom_work_dir, "cloud_init_script.sh") }

      before do
        allow(File).to receive(:join).and_call_original
        allow(File).to receive(:join).with(custom_work_dir, "cloud_init_script.sh").and_return(custom_file_path)
      end

      it 'uses the provided work directory' do
        expect(File).to receive(:write).with(custom_file_path, script_content)
        result = service.write_script_to_file(node.id, custom_work_dir)
        expect(result).to eq(custom_file_path)
      end
    end
  end
end
