class ProvisionDefaultCredentialJob < ApplicationJob
  queue_as :default

  # Provision a default database credential for a primary node
  # This is triggered when a primary node becomes active for the first time
  def perform(node_id)
    @node = Node.find_by_id(node_id)
    return unless @node

    Rails.logger.info "ProvisionDefaultCredentialJob: Starting for node #{@node.id} (#{@node.name})"

    # Only provision for primary nodes
    unless @node.primary?
      Rails.logger.info "ProvisionDefaultCredentialJob: Skipping - node #{@node.id} is not a primary node"
      return
    end

    # Only provision if node is active
    unless @node.active?
      Rails.logger.info "ProvisionDefaultCredentialJob: Skipping - node #{@node.id} is not active"
      return
    end

    # Check if a default credential already exists
    # Note: username is encrypted, so we need to check each credential
    existing_default = @node.credentials.find { |c| c.username == "default" }
    if existing_default
      Rails.logger.info "ProvisionDefaultCredentialJob: Default credential already exists for node #{@node.id}"
      return
    end

    # Create the default credential
    credential = create_default_credential

    if credential.persisted?
      Rails.logger.info "ProvisionDefaultCredentialJob: Created default credential #{credential.id} for node #{@node.id}"
      
      # Provision the credential on the appropriate nodes
      provision_credential_on_nodes(credential)
    else
      Rails.logger.error "ProvisionDefaultCredentialJob: Failed to create default credential for node #{@node.id}: #{credential.errors.full_messages.join(', ')}"
    end
  rescue => e
    Rails.logger.error "ProvisionDefaultCredentialJob: Error for node #{node_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end

  private

  def create_default_credential
    # Generate a secure random password
    password = SecureRandom.alphanumeric(32)

    # Create the credential record
    credential = @node.credentials.build(
      username: "default",
      password: password
    )

    credential.save
    credential
  end

  def provision_credential_on_nodes(credential)
    database_type_handler = @node.database_type_handler

    if database_type_handler.users_replicate_automatically?
      # Users are automatically replicated - only create on primary
      Rails.logger.info "ProvisionDefaultCredentialJob: Database type #{@node.database_type_slug} auto-replicates users - provisioning on primary only"
      provision_on_node(@node, credential)
    else
      # Users must be created on each node - provision on primary and all active replicas
      Rails.logger.info "ProvisionDefaultCredentialJob: Database type #{@node.database_type_slug} requires manual user replication - provisioning on all nodes"
      
      # Provision on primary
      provision_on_node(@node, credential)
      
      # Provision on all active replicas
      @node.replicas.active.each do |replica|
        Rails.logger.info "ProvisionDefaultCredentialJob: Provisioning on replica #{replica.id} (#{replica.name})"
        provision_on_node(replica, credential)
      end
    end
  end

  def provision_on_node(node, credential)
    deployment_service = node.deployment_service
    
    begin
      deployment_service.create_user!(
        credential.username,
        credential.password,
        default_privileges_for_database_type
      )
      Rails.logger.info "ProvisionDefaultCredentialJob: Successfully provisioned user '#{credential.username}' on node #{node.id}"
    rescue => e
      Rails.logger.error "ProvisionDefaultCredentialJob: Failed to provision user on node #{node.id}: #{e.message}"
      raise e
    end
  end

  def default_privileges_for_database_type
    # Return appropriate default privileges based on database type
    case @node.database_type_slug
    when "postgresql"
      "ALL"
    when "mysql"
      "*.*:ALL"
    when "mongodb"
      [ "readWrite", "dbAdmin" ]
    when "cassandra"
      [ "LOGIN", "SELECT", "MODIFY" ]
    else
      nil
    end
  end
end

