require 'rails_helper'

RSpec.describe DeploymentServices::BaseDeploymentService, type: :service do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:service) { DeploymentServices::BaseDeploymentService.new(node) }

  describe '#initialize' do
    it 'sets the node' do
      expect(service.node).to eq(node)
    end
  end

  describe '#deploy_primary!' do
    it 'raises NotImplementedError' do
      expect { service.deploy_primary! }.to raise_error(NotImplementedError, "DeploymentServices::BaseDeploymentService must implement #deploy_primary!")
    end
  end

  describe '#deploy_replica!' do
    it 'raises NotImplementedError' do
      expect { service.deploy_replica! }.to raise_error(NotImplementedError, "DeploymentServices::BaseDeploymentService must implement #deploy_replica!")
    end
  end

  describe '#configure_replication!' do
    it 'raises NotImplementedError' do
      expect { service.configure_replication! }.to raise_error(NotImplementedError, "DeploymentServices::BaseDeploymentService must implement #configure_replication!")
    end
  end

  describe '#cleanup_replication!' do
    it 'raises NotImplementedError' do
      expect { service.cleanup_replication! }.to raise_error(NotImplementedError, "DeploymentServices::BaseDeploymentService must implement #cleanup_replication!")
    end
  end

  describe '#create_user!' do
    it 'raises NotImplementedError' do
      expect { service.create_user!('test', 'password') }.to raise_error(NotImplementedError, "DeploymentServices::BaseDeploymentService must implement #create_user!")
    end
  end

  describe '#destroy_user!' do
    it 'raises NotImplementedError' do
      expect { service.destroy_user!('test') }.to raise_error(NotImplementedError, "DeploymentServices::BaseDeploymentService must implement #destroy_user!")
    end
  end

  describe 'protected methods' do
    describe '#database_type_handler' do
      it 'returns the node database type handler' do
        handler = double('database_type_handler')
        allow(node).to receive(:database_type_handler).and_return(handler)
        
        expect(service.send(:database_type_handler)).to eq(handler)
      end

      it 'memoizes the database type handler' do
        handler = double('database_type_handler')
        allow(node).to receive(:database_type_handler).and_return(handler)
        
        # Call twice to test memoization
        service.send(:database_type_handler)
        service.send(:database_type_handler)
        
        expect(node).to have_received(:database_type_handler).once
      end
    end

    describe '#ansible_service' do
      it 'returns an AnsibleRunService instance' do
        expect(service.send(:ansible_service)).to be_a(AnsibleRunService)
      end

      it 'memoizes the ansible service' do
        service1 = service.send(:ansible_service)
        service2 = service.send(:ansible_service)
        
        expect(service1).to be(service2)
      end
    end

    describe '#cloud_init_service' do
      it 'returns a CloudInitService instance' do
        expect(service.send(:cloud_init_service)).to be_a(CloudInitService)
      end

      it 'memoizes the cloud init service' do
        service1 = service.send(:cloud_init_service)
        service2 = service.send(:cloud_init_service)
        
        expect(service1).to be(service2)
      end
    end

    describe '#run_ansible_playbook' do
      let(:playbook) { 'test_playbook.yml' }
      let(:vars) { { 'custom_var' => 'value' } }
      let(:ansible_service) { instance_double(AnsibleRunService) }

      before do
        allow(service).to receive(:ansible_service).and_return(ansible_service)
        allow(node).to receive(:database_type_slug).and_return('postgresql')
        allow(node).to receive(:database_version).and_return('15')
      end

      it 'calls ansible service with merged vars' do
        expected_vars = {
          'postgresql_version' => '15',
          'custom_var' => 'value'
        }
        
        expect(ansible_service).to receive(:perform).with(node.id, playbook, vars: expected_vars)
        
        service.send(:run_ansible_playbook, playbook, vars)
      end

      it 'includes database version in default vars' do
        expect(ansible_service).to receive(:perform).with(
          node.id, 
          playbook, 
          vars: { 'postgresql_version' => '15' }
        )
        
        service.send(:run_ansible_playbook, playbook)
      end

      it 'allows custom vars to override default vars' do
        custom_vars = { 'postgresql_version' => '14', 'other_var' => 'test' }
        expected_vars = {
          'postgresql_version' => '14',
          'other_var' => 'test'
        }
        
        expect(ansible_service).to receive(:perform).with(node.id, playbook, vars: expected_vars)
        
        service.send(:run_ansible_playbook, playbook, custom_vars)
      end
    end
  end
end
