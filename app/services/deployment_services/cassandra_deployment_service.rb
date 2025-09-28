require_relative "base_deployment_service"

module DeploymentServices
  class CassandraDeploymentService < BaseDeploymentService
    def deploy_primary!
      run_ansible_playbook(database_type_handler.primary_playbook, {
        cluster_name: cluster_name,
        seeds: seeds_list,
        listen_address: node.get_ip_address,
        replication_factor: default_replication_factor
      })
    end

    def deploy_replica!
      # In Cassandra, we add nodes to the cluster rather than create replicas
      primary_node = node.parent_node
      return false unless primary_node

      run_ansible_playbook(database_type_handler.replica_playbook, {
        cluster_name: cluster_name,
        seeds: seeds_list,
        listen_address: node.get_ip_address,
        primary_ip: primary_node.get_ip_address,
        replication_factor: default_replication_factor
      })
    end

    def configure_replication!
      return false unless node.primary?

      additional_nodes = node.replicas.where(status: "active")
      return true if additional_nodes.empty?

      additional_nodes.each do |additional_node|
        run_ansible_playbook(database_type_handler.primary_replication_playbook, {
          cluster_name: cluster_name,
          new_node_ip: additional_node.get_ip_address,
          seeds: seeds_list,
          replication_factor: calculate_replication_factor
        })
      end

      true
    end

    def cleanup_replication!
      return false unless node.replica?

      primary_node = node.parent_node
      return false unless primary_node

      run_ansible_playbook(database_type_handler.cleanup_playbook, {
        cluster_name: cluster_name,
        node_ip: node.get_ip_address,
        seeds: seeds_list_without_node
      })
    end

    def create_user!(username, password, privileges = nil)
      # Cassandra uses roles instead of traditional users
      default_privileges = privileges || ["LOGIN"]
      
      run_ansible_playbook(database_type_handler.create_user_playbook, {
        username: username,
        password: password,
        privileges: default_privileges,
        superuser: privileges&.include?("SUPERUSER") || false
      })
    end

    def destroy_user!(username)
      run_ansible_playbook(database_type_handler.destroy_user_playbook, {
        username: username
      })
    end

    # Cassandra-specific methods
    def create_keyspace!(keyspace_name, replication_factor = nil)
      rf = replication_factor || calculate_replication_factor
      
      run_ansible_playbook("create_keyspace.yml", {
        keyspace_name: keyspace_name,
        replication_factor: rf,
        cluster_name: cluster_name
      })
    end

    def drop_keyspace!(keyspace_name)
      run_ansible_playbook("drop_keyspace.yml", {
        keyspace_name: keyspace_name
      })
    end

    def backup_keyspace(keyspace_name = nil)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      snapshot_name = "backup_#{node.id}_#{timestamp}"

      run_ansible_playbook("backup_keyspace.yml", {
        keyspace_name: keyspace_name,
        snapshot_name: snapshot_name,
        backup_path: "/var/backups/cassandra"
      })
    end

    def restore_keyspace(keyspace_name, snapshot_name)
      run_ansible_playbook("restore_keyspace.yml", {
        keyspace_name: keyspace_name,
        snapshot_name: snapshot_name,
        backup_path: "/var/backups/cassandra"
      })
    end

    def check_cluster_status
      run_ansible_playbook("check_cluster_status.yml", {
        cluster_name: cluster_name
      })
    end

    def repair_keyspace(keyspace_name = nil)
      run_ansible_playbook("repair_keyspace.yml", {
        keyspace_name: keyspace_name
      })
    end

    def cleanup_node
      run_ansible_playbook("cleanup_node.yml", {
        cluster_name: cluster_name
      })
    end

    def add_node_to_cluster(new_node)
      return false unless node.primary?
      return false unless new_node.cluster == node.cluster

      run_ansible_playbook(database_type_handler.primary_replication_playbook, {
        cluster_name: cluster_name,
        new_node_ip: new_node.get_ip_address,
        seeds: seeds_list,
        replication_factor: calculate_replication_factor
      })
    end

    def remove_node_from_cluster(target_node)
      return false unless node.primary?

      run_ansible_playbook(database_type_handler.cleanup_playbook, {
        cluster_name: cluster_name,
        node_ip: target_node.get_ip_address,
        seeds: seeds_list_without_node(target_node)
      })
    end

    def scale_cluster(target_size)
      current_size = cluster_nodes.count
      return true if current_size == target_size

      if target_size > current_size
        # Scale up - add nodes
        (target_size - current_size).times do |i|
          run_ansible_playbook("add_node.yml", {
            cluster_name: cluster_name,
            seeds: seeds_list,
            replication_factor: calculate_replication_factor
          })
        end
      else
        # Scale down - remove nodes (be careful with this)
        nodes_to_remove = cluster_nodes.limit(current_size - target_size)
        nodes_to_remove.each do |node_to_remove|
          remove_node_from_cluster(node_to_remove)
        end
      end
    end

    def get_cluster_metrics
      run_ansible_playbook("get_cluster_metrics.yml", {
        cluster_name: cluster_name
      })
    end

    def flush_memtables
      run_ansible_playbook("flush_memtables.yml")
    end

    def compact_keyspace(keyspace_name = nil)
      run_ansible_playbook("compact_keyspace.yml", {
        keyspace_name: keyspace_name
      })
    end

    private

    def cluster_name
      @cluster_name ||= "#{node.cluster.name.downcase.gsub(/[^a-z0-9]/, "_")}_cluster"
    end

    def cluster_nodes
      @cluster_nodes ||= node.cluster.nodes.where(status: "active")
    end

    def seeds_list
      # Use the first 3 nodes as seeds, or all nodes if less than 3
      seed_nodes = cluster_nodes.limit(3)
      seed_nodes.map(&:get_ip_address).compact.join(",")
    end

    def seeds_list_without_node(excluded_node = nil)
      excluded_node ||= node
      seed_nodes = cluster_nodes.where.not(id: excluded_node.id).limit(3)
      seed_nodes.map(&:get_ip_address).compact.join(",")
    end

    def default_replication_factor
      1
    end

    def calculate_replication_factor
      # Calculate optimal replication factor based on cluster size
      cluster_size = cluster_nodes.count
      
      case cluster_size
      when 1
        1
      when 2..3
        2
      when 4..6
        3
      else
        # For larger clusters, use 3 as default but could be configurable
        3
      end
    end
  end
end
