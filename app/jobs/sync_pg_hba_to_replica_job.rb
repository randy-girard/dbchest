class SyncPgHbaToReplicaJob < ApplicationJob
  queue_as :default

  # Sync pg_hba.conf entry on a PostgreSQL replica
  # @param replica_node_id [Integer] The ID of the replica node
  # @param username [String] The username to add/remove from pg_hba.conf
  # @param action [String] Either 'add' or 'remove'
  def perform(replica_node_id, username, action)
    @replica_node = Node.find_by_id(replica_node_id)
    return unless @replica_node
    return unless @replica_node.replica?
    return unless @replica_node.database_type_slug == "postgresql"

    Rails.logger.info "SyncPgHbaToReplicaJob: #{action.upcase} pg_hba entry for user '#{username}' on replica #{@replica_node.id} (#{@replica_node.name})"

    # Check if database type supports automatic user replication
    database_type_handler = @replica_node.database_type_handler
    unless database_type_handler.respond_to?(:users_replicate_automatically?) && database_type_handler.users_replicate_automatically?
      Rails.logger.info "SyncPgHbaToReplicaJob: Skipping - database type #{@replica_node.database_type_slug} does not auto-replicate users"
      return
    end

    # Run Ansible playbook to sync pg_hba.conf
    begin
      vars = {
        username: username,
        action: action,
        postgresql_version: @replica_node.database_type_version&.version || "15"
      }

      result = AnsibleRunService.new.perform(@replica_node.id, "sync_replica_pg_hba.yml", vars: vars)

      if result[:success]
        Rails.logger.info "SyncPgHbaToReplicaJob: Successfully #{action}ed pg_hba entry for user '#{username}' on replica #{@replica_node.id}"
      else
        Rails.logger.error "SyncPgHbaToReplicaJob: Failed to #{action} pg_hba entry for user '#{username}' on replica #{@replica_node.id}: #{result[:error]}"
      end
    rescue => e
      Rails.logger.error "SyncPgHbaToReplicaJob: Error syncing pg_hba for user '#{username}' on replica #{@replica_node.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end
