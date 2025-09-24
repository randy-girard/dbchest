module DeploymentServices
  class BaseDeploymentService
    attr_reader :node

    def initialize(node)
      @node = node
    end

    def deploy_primary!
      raise NotImplementedError, "#{self.class} must implement #deploy_primary!"
    end

    def deploy_replica!
      raise NotImplementedError, "#{self.class} must implement #deploy_replica!"
    end

    def configure_replication!
      raise NotImplementedError, "#{self.class} must implement #configure_replication!"
    end

    def cleanup_replication!
      raise NotImplementedError, "#{self.class} must implement #cleanup_replication!"
    end

    def create_user!(username, password, privileges = nil)
      raise NotImplementedError, "#{self.class} must implement #create_user!"
    end

    def destroy_user!(username)
      raise NotImplementedError, "#{self.class} must implement #destroy_user!"
    end

    protected

    def database_type_handler
      @database_type_handler ||= node.database_type_handler
    end

    def ansible_service
      @ansible_service ||= AnsibleRunService.new
    end

    def cloud_init_service
      @cloud_init_service ||= CloudInitService.new
    end

    def run_ansible_playbook(playbook, vars = {})
      # Add database version to vars
      default_vars = {
        "#{node.database_type_slug}_version" => node.database_version
      }
      ansible_service.perform(node.id, playbook, vars: default_vars.merge(vars))
    end
  end
end
