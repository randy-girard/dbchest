require_relative "base_deployment_service"

module DeploymentServices
  class MysqlDeploymentService < BaseDeploymentService
    def deploy_primary!
      run_ansible_playbook(database_type_handler.primary_playbook, {
        mysql_root_password: get_root_password
      })
    end

    def deploy_replica!
      primary_node = node.parent_node
      return false unless primary_node

      run_ansible_playbook(database_type_handler.replica_playbook, {
        primary_host: primary_node.get_ip_address,
        replication_password: primary_node.get_replication_password,
        mysql_root_password: get_root_password
      })
    end

    def configure_replication!
      return false unless node.primary?

      # Ensure replication password exists
      node.ensure_replication_password!

      run_ansible_playbook(database_type_handler.primary_replication_playbook, {
        replication_password: node.get_replication_password,
        mysql_root_password: get_root_password
      })
    end

    def cleanup_replication!
      run_ansible_playbook(database_type_handler.cleanup_playbook, {
        mysql_root_password: get_root_password
      })
    end

    def create_user!(username, password, privileges = nil)
      # MySQL privileges format: "database.table:PRIVILEGE1,PRIVILEGE2"
      # Default: "*.*:ALL" means all privileges on all databases
      default_privileges = privileges || "*.*:ALL"

      run_ansible_playbook(database_type_handler.create_user_playbook, {
        username: username,
        password: password,
        privileges: default_privileges,
        host: '%',  # Allow connections from any host
        mysql_root_password: get_root_password
      })
    end

    def destroy_user!(username)
      run_ansible_playbook(database_type_handler.destroy_user_playbook, {
        username: username,
        mysql_root_password: get_root_password
      })
    end

    def backup_database(database_name = nil, backup_file = nil)
      # MySQL-specific backup logic
      backup_file ||= "backup_#{node.id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.sql"

      run_ansible_playbook("mysql/backup_database.yml", {
        database_name: database_name || "--all-databases",
        backup_file: backup_file,
        mysql_root_password: get_root_password
      })
    end

    def restore_database(database_name, backup_file)
      # MySQL-specific restore logic
      run_ansible_playbook("mysql/restore_database.yml", {
        database_name: database_name,
        backup_file: backup_file,
        mysql_root_password: get_root_password
      })
    end

    def check_replication_status
      # MySQL-specific replication status check
      if node.replica?
        run_ansible_playbook("mysql/check_replica_status.yml", {
          mysql_root_password: get_root_password
        })
      else
        run_ansible_playbook("mysql/check_primary_status.yml", {
          mysql_root_password: get_root_password
        })
      end
    end

    private

    def get_root_password
      # Retrieve the stored root password from the node
      # This password is set during node creation and stored encrypted
      node.ensure_root_password!
    end
  end
end
