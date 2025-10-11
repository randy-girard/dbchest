class SyncCredentialsToReplicaJob < ApplicationJob
  queue_as :default

  # Synchronize credentials from primary to replica when replica becomes active
  def perform(replica_node_id)
    @replica_node = Node.find_by_id(replica_node_id)
    return unless @replica_node
    return unless @replica_node.replica?
    return unless @replica_node.parent_node.present?

    Rails.logger.info "SyncCredentialsToReplicaJob: Starting for replica #{@replica_node.id} (#{@replica_node.name})"

    # Check if database type supports automatic user replication
    database_type_handler = @replica_node.database_type_handler
    unless database_type_handler.respond_to?(:users_replicate_automatically?) && database_type_handler.users_replicate_automatically?
      Rails.logger.info "SyncCredentialsToReplicaJob: Skipping - database type #{@replica_node.database_type_slug} does not auto-replicate users"
      return
    end

    primary_node = @replica_node.parent_node

    # Get all credentials from primary (excluding already replicated ones)
    primary_credentials = primary_node.credentials.where(is_replicated: false)

    Rails.logger.info "SyncCredentialsToReplicaJob: Found #{primary_credentials.count} credentials on primary to replicate"

    primary_credentials.each do |primary_credential|
      # Check if this credential is already replicated to this replica
      existing_replica_credential = @replica_node.credentials.find_by(
        source_credential_id: primary_credential.id
      )

      if existing_replica_credential
        Rails.logger.info "SyncCredentialsToReplicaJob: Credential '#{primary_credential.username}' already exists on replica"
        next
      end

      # Create replicated credential on replica
      begin
        replica_credential = @replica_node.credentials.create!(
          username: primary_credential.username,
          password: primary_credential.password,
          source_credential_id: primary_credential.id,
          is_replicated: true,
          skip_default_credential_protection: true
        )
        Rails.logger.info "SyncCredentialsToReplicaJob: Successfully replicated credential '#{primary_credential.username}' to replica"

        # Sync pg_hba.conf entry for PostgreSQL replicas
        if @replica_node.database_type_slug == "postgresql"
          Rails.logger.info "SyncCredentialsToReplicaJob: Syncing pg_hba entry for '#{primary_credential.username}'"
          SyncPgHbaToReplicaJob.perform_later(@replica_node.id, primary_credential.username, "add")
        end
      rescue => e
        Rails.logger.error "SyncCredentialsToReplicaJob: Failed to replicate credential '#{primary_credential.username}': #{e.message}"
      end
    end

    Rails.logger.info "SyncCredentialsToReplicaJob: Completed for replica #{@replica_node.id}"
  end
end
