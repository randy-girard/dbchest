require_relative 'base_deployment_service'

module DeploymentServices
  class PostgresqlDeploymentService < BaseDeploymentService
    def deploy_primary!
      run_ansible_playbook(database_type_handler.primary_playbook, {
        postgres_password: SecureRandom.alphanumeric(32)
      })
    end

    def deploy_replica!
      primary_node = node.parent_node
      return false unless primary_node

      run_ansible_playbook(database_type_handler.replica_playbook, {
        primary_ip: primary_node.get_ip_address,
        replication_password: primary_node.get_replication_password,
        replica_node_name: node.name.downcase.gsub(/[^a-z0-9]/, '-')
      })
    end

    def configure_replication!
      return false unless node.primary?

      # Ensure replication password exists
      node.ensure_replication_password!
      
      run_ansible_playbook(database_type_handler.primary_replication_playbook, {
        replication_password: node.get_replication_password
      })
    end

    def cleanup_replication!
      run_ansible_playbook(database_type_handler.cleanup_playbook)
    end

    def create_user!(username, password, privileges = nil)
      run_ansible_playbook(database_type_handler.create_user_playbook, {
        username: username,
        password: password,
        privileges: privileges || "ALL"
      })
    end

    def destroy_user!(username)
      run_ansible_playbook(database_type_handler.destroy_user_playbook, {
        username: username
      })
    end

    def backup_database(database_name = nil)
      # PostgreSQL-specific backup logic
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      backup_file = "backup_#{node.id}_#{timestamp}.sql"
      
      run_ansible_playbook("backup_database.yml", {
        database_name: database_name || "all",
        backup_file: backup_file
      })
    end

    def restore_database(backup_file, database_name = nil)
      # PostgreSQL-specific restore logic
      run_ansible_playbook("restore_database.yml", {
        database_name: database_name,
        backup_file: backup_file
      })
    end

    def check_replication_status
      # PostgreSQL-specific replication status check
      if node.replica?
        run_ansible_playbook("check_replica_status.yml")
      else
        run_ansible_playbook("check_primary_status.yml")
      end
    end
  end
end
