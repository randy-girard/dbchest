class Credential < ApplicationRecord
  belongs_to :node
  belongs_to :source_credential, class_name: "Credential", optional: true
  has_many :replicated_credentials, class_name: "Credential", foreign_key: :source_credential_id, dependent: :delete_all

  validates :username, presence: true
  validate :username_cannot_be_changed, on: :update
  validate :password_cannot_be_changed, on: :update
  validate :cannot_create_on_replica, on: :create
  validate :cannot_delete_replicated_credential, on: :destroy

  encrypts :username,
           :password

  # Attribute to allow bypassing deletion protection
  attr_accessor :skip_default_credential_protection

  # Callbacks
  before_destroy :prevent_default_credential_deletion, unless: :skip_default_credential_protection
  before_destroy :prevent_replicated_credential_deletion
  after_create :replicate_to_replicas
  after_create :sync_pg_hba_to_replicas, if: :should_sync_pg_hba?
  after_destroy :remove_pg_hba_from_replicas, if: :should_sync_pg_hba?

  def provision!
    CreateCredentialsService.perform_async(id)
  end

  def deprovision!
    DestroyCredentialsService.perform_async(id)
  end

  def default_credential?
    username == "default"
  end

  # Connection string helpers
  def connection_strings
    return {} unless node&.active?

    ip_address = node.get_ip_address
    return {} unless ip_address

    database_type = node.database_type_slug
    port = node.database_type_version&.default_port

    case database_type
    when "postgresql"
      postgresql_connection_strings(ip_address, port)
    when "mysql"
      mysql_connection_strings(ip_address, port)
    when "mongodb"
      mongodb_connection_strings(ip_address, port)
    when "cassandra"
      cassandra_connection_strings(ip_address, port)
    else
      {}
    end
  end

  private

  def postgresql_connection_strings(ip_address, port)
    {
      psql: "psql -h #{ip_address} -p #{port} -U #{username} -d postgres",
      uri: "postgresql://#{username}:#{password}@#{ip_address}:#{port}/postgres",
      jdbc: "jdbc:postgresql://#{ip_address}:#{port}/postgres?user=#{username}&password=#{password}",
      connection_string: "host=#{ip_address} port=#{port} user=#{username} password=#{password} dbname=postgres",
      rails: {
        adapter: "postgresql",
        host: ip_address,
        port: port,
        username: username,
        password: password,
        database: "postgres"
      }
    }
  end

  def mysql_connection_strings(ip_address, port)
    {
      mysql: "mysql -h #{ip_address} -P #{port} -u #{username} -p#{password}",
      uri: "mysql://#{username}:#{password}@#{ip_address}:#{port}/",
      jdbc: "jdbc:mysql://#{ip_address}:#{port}/?user=#{username}&password=#{password}",
      connection_string: "server=#{ip_address};port=#{port};uid=#{username};pwd=#{password}",
      rails: {
        adapter: "mysql2",
        host: ip_address,
        port: port,
        username: username,
        password: password
      }
    }
  end

  def mongodb_connection_strings(ip_address, port)
    {
      mongo: "mongosh \"mongodb://#{username}:#{password}@#{ip_address}:#{port}/admin\"",
      uri: "mongodb://#{username}:#{password}@#{ip_address}:#{port}/admin",
      connection_string: "mongodb://#{username}:#{password}@#{ip_address}:#{port}/admin?authSource=admin",
      rails: {
        adapter: "mongoid",
        hosts: [ "#{ip_address}:#{port}" ],
        database: "admin",
        options: {
          user: username,
          password: password,
          auth_source: "admin"
        }
      }
    }
  end

  def cassandra_connection_strings(ip_address, port)
    {
      cqlsh: "cqlsh #{ip_address} #{port} -u #{username} -p #{password}",
      connection_string: "contact_points=#{ip_address};port=#{port};username=#{username};password=#{password}",
      driver: {
        contact_points: [ ip_address ],
        port: port,
        username: username,
        password: password
      }
    }
  end

  def prevent_default_credential_deletion
    if default_credential?
      errors.add(:base, "Cannot delete the default credential")
      throw(:abort)
    end
  end

  def username_cannot_be_changed
    if username_changed? && persisted?
      errors.add(:username, "cannot be changed after creation")
    end
  end

  def password_cannot_be_changed
    if password_changed? && persisted?
      errors.add(:password, "cannot be changed after creation")
    end
  end

  def cannot_create_on_replica
    return unless node&.replica?
    return unless node.parent_node.present?

    # Check if database type supports automatic user replication
    database_type_handler = node.database_type_handler
    return unless database_type_handler.respond_to?(:users_replicate_automatically?) && database_type_handler.users_replicate_automatically?

    # Don't allow creating credentials on replicas (unless it's a replicated credential being synced)
    unless is_replicated?
      errors.add(:base, "Cannot create credentials on a replica node. Create credentials on the primary node instead.")
    end
  end

  def cannot_delete_replicated_credential
    # This is called during validation, not in before_destroy
    # We'll handle this in prevent_replicated_credential_deletion
  end

  def prevent_replicated_credential_deletion
    # Allow deletion if it's being deleted via the source_credential association (cascade delete)
    # or if the skip flag is set
    return if skip_default_credential_protection
    return unless is_replicated?

    # Check if this is being deleted as part of a cascade from the source credential
    # If the source credential is being destroyed, allow this deletion
    return if source_credential&.destroyed? || source_credential&.marked_for_destruction?

    errors.add(:base, "Cannot delete replicated credentials. Delete the credential from the primary node instead.")
    throw(:abort)
  end

  def replicate_to_replicas
    return if is_replicated? # Don't replicate replicated credentials
    return unless node&.primary?

    # Check if database type supports automatic user replication
    database_type_handler = node.database_type_handler
    return unless database_type_handler.respond_to?(:users_replicate_automatically?) && database_type_handler.users_replicate_automatically?

    # Create credential records on all active replicas
    node.replicas.active.each do |replica|
      replica.credentials.create!(
        username: username,
        password: password,
        source_credential_id: id,
        is_replicated: true,
        skip_default_credential_protection: true
      )
    end
  rescue => e
    # Log error but don't fail the credential creation
    Rails.logger.error "Failed to replicate credential to replicas: #{e.message}"
  end



  # Get all credentials visible for this node (including replicated ones)
  def self.visible_for_node(node)
    if node.replica? && node.parent_node.present?
      database_type_handler = node.database_type_handler
      if database_type_handler.respond_to?(:users_replicate_automatically?) && database_type_handler.users_replicate_automatically?
        # Show both local credentials and credentials from primary
        node.credentials
      else
        # Only show local credentials
        node.credentials.where(is_replicated: false)
      end
    else
      # Primary node or standalone - show all credentials
      node.credentials
    end
  end

  private

  # Check if we should sync pg_hba.conf entries to replicas
  def should_sync_pg_hba?
    return false if is_replicated? # Don't sync for replicated credentials
    return false unless node&.primary? # Only sync from primary nodes
    return false unless node.database_type_slug == "postgresql" # Only for PostgreSQL

    database_type_handler = node.database_type_handler
    return false unless database_type_handler.respond_to?(:users_replicate_automatically?) && database_type_handler.users_replicate_automatically?

    true
  end

  # Sync pg_hba.conf entries to all active replicas when credential is created
  def sync_pg_hba_to_replicas
    node.replicas.active.each do |replica|
      SyncPgHbaToReplicaJob.perform_later(replica.id, username, "add")
    end
  rescue => e
    Rails.logger.error "Failed to sync pg_hba to replicas: #{e.message}"
  end

  # Remove pg_hba.conf entries from all replicas when credential is deleted
  def remove_pg_hba_from_replicas
    node.replicas.active.each do |replica|
      SyncPgHbaToReplicaJob.perform_later(replica.id, username, "remove")
    end
  rescue => e
    Rails.logger.error "Failed to remove pg_hba from replicas: #{e.message}"
  end
end
