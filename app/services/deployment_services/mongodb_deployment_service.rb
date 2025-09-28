require_relative "base_deployment_service"

module DeploymentServices
  class MongodbDeploymentService < BaseDeploymentService
    def deploy_primary!
      run_ansible_playbook(database_type_handler.primary_playbook, {
        mongodb_root_password: SecureRandom.alphanumeric(32),
        replica_set_name: replica_set_name
      })
    end

    def deploy_replica!
      primary_node = node.parent_node
      return false unless primary_node

      run_ansible_playbook(database_type_handler.replica_playbook, {
        primary_ip: primary_node.get_ip_address,
        mongodb_root_password: primary_node.get_replication_password,
        replica_set_name: replica_set_name
      })
    end

    def configure_replication!
      return false unless node.primary?

      replica_nodes = node.replicas.where(status: "active")
      return true if replica_nodes.empty?

      replica_nodes.each do |replica|
        run_ansible_playbook(database_type_handler.primary_replication_playbook, {
          replica_ip: replica.get_ip_address,
          mongodb_root_password: node.get_replication_password,
          replica_set_name: replica_set_name
        })
      end

      true
    end

    def cleanup_replication!
      return false unless node.replica?

      primary_node = node.parent_node
      return false unless primary_node

      run_ansible_playbook(database_type_handler.cleanup_playbook, {
        replica_ip: node.get_ip_address,
        mongodb_root_password: primary_node.get_replication_password,
        replica_set_name: replica_set_name
      })
    end

    def create_user!(username, password, privileges = nil)
      default_privileges = privileges || ["readWrite"]
      
      run_ansible_playbook(database_type_handler.create_user_playbook, {
        username: username,
        password: password,
        privileges: default_privileges,
        database: "admin",
        mongodb_root_password: node.get_replication_password || SecureRandom.alphanumeric(32)
      })
    end

    def destroy_user!(username)
      run_ansible_playbook(database_type_handler.destroy_user_playbook, {
        username: username,
        database: "admin",
        mongodb_root_password: node.get_replication_password || SecureRandom.alphanumeric(32)
      })
    end

    # MongoDB-specific methods
    def backup_database(database_name = nil)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      backup_file = "mongodb_backup_#{node.id}_#{timestamp}"

      run_ansible_playbook("backup_database.yml", {
        database_name: database_name || "all",
        backup_file: backup_file,
        mongodb_root_password: node.get_replication_password
      })
    end

    def restore_database(backup_file, database_name = nil)
      run_ansible_playbook("restore_database.yml", {
        database_name: database_name,
        backup_file: backup_file,
        mongodb_root_password: node.get_replication_password
      })
    end

    def check_replication_status
      if node.replica?
        run_ansible_playbook("check_replica_status.yml", {
          mongodb_root_password: node.parent_node.get_replication_password
        })
      else
        run_ansible_playbook("check_primary_status.yml", {
          mongodb_root_password: node.get_replication_password
        })
      end
    end

    def get_replica_set_status
      run_ansible_playbook("get_replica_set_status.yml", {
        mongodb_root_password: node.get_replication_password,
        replica_set_name: replica_set_name
      })
    end

    def add_replica_to_set(replica_node)
      return false unless node.primary?
      return false unless replica_node.replica?

      run_ansible_playbook(database_type_handler.primary_replication_playbook, {
        replica_ip: replica_node.get_ip_address,
        mongodb_root_password: node.get_replication_password,
        replica_set_name: replica_set_name
      })
    end

    def remove_replica_from_set(replica_node)
      return false unless node.primary?

      run_ansible_playbook(database_type_handler.cleanup_playbook, {
        replica_ip: replica_node.get_ip_address,
        mongodb_root_password: node.get_replication_password,
        replica_set_name: replica_set_name
      })
    end

    private

    def replica_set_name
      @replica_set_name ||= "#{node.cluster.name.downcase.gsub(/[^a-z0-9]/, "_")}_rs"
    end
  end
end
