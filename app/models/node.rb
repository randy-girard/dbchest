require_relative "../services/database_service_factory"

class Node < ApplicationRecord
  include NodeStatusManagement
  include NodeMetricsManagement
  include NodeIpAddressManagement

  belongs_to :cluster
  belongs_to :provider
  belongs_to :parent_node, class_name: "Node", optional: true
  belongs_to :database_type_version

  has_many :credentials, dependent: :destroy
  has_many :node_settings, dependent: :destroy
  # node_metrics and monitoring_configs are defined in NodeMetricsManagement concern
  has_many :replicas, class_name: "Node", foreign_key: "parent_node_id", dependent: :destroy
  accepts_nested_attributes_for :node_settings

  validates :name, presence: true, uniqueness: { scope: :cluster_id }
  validates :provider, presence: true
  validate :parent_node_must_be_primary
  validate :database_type_version_matches_cluster
  validate :replica_version_matches_primary

  # Scopes
  scope :primary, -> { where(parent_node_id: nil) }
  scope :replicas, -> { where.not(parent_node_id: nil) }
  scope :active, -> { where(status: "active") }
  scope :with_status, ->(status) { where(status: status) }
  scope :recent, -> { order(created_at: :desc) }

  # Ensure database version is set
  before_validation :set_default_database_type_version, on: :create

  # Generate SSH keys and root password on creation
  after_create :ensure_ssh_keys_and_password

  after_destroy :cleanup_parent_replication_config, if: :replica?

  encrypts :terraform_state,
           :ssh_public_key,
           :ssh_private_key,
           :runtime_config,
           :replication_password,
           :root_password,
           :metrics_api_key

  def build_node_settings!
    provider.provider_type.provider_type_node_options.each do |option|
      unless node_settings.exists?(key: option.key)
        self.node_settings.build(
          provider_type_node_option_id: option.id,
          key: option.key)
      end
    end
  end

  def provider_api_client
    provider.api_client
  end

  def exists_in_provider?
    provider_api_client.exists?(self)
  end

  def provision!
    CreateService.perform_async(id)
  end

  def deprovision!
    DestroyService.perform_async(id)
  end

  def primary?
    parent_node_id.nil?
  end

  def replica?
    parent_node_id.present?
  end

  def has_replicas?
    replicas.any?
  end

  def can_create_replicas?
    primary? && active?
  end

  # Database version-related methods
  def database_version
    database_type_version&.version
  end

  def database_type_name
    database_type_version&.database_type&.name
  end

  def database_type_slug
    database_type_version&.database_type&.slug
  end

  def supports_logical_replication?
    database_type_version&.supports_logical_replication? || false
  end

  def supports_streaming_replication?
    database_type_version&.supports_streaming_replication? || false
  end

  def replication_method_for(target_node)
    return nil unless target_node.is_a?(Node)
    return nil unless target_node.database_type_version
    return nil unless database_type_version&.database_type_id == target_node.database_type_version.database_type_id

    database_type_version.replication_method_for_cross_version(target_node.database_type_version)
  end

  def database_type_handler
    @database_type_handler ||= database_type_version&.database_type_handler
  end

  def available_database_versions
    cluster&.available_versions || []
  end

  def provision_replica!
    return false unless parent_node_id.present?
    return false unless parent_node&.active?

    CreateService.perform_async(id, true)
  end

  def deployment_service
    @deployment_service ||= DatabaseServiceFactory.deployment_service_for(self)
  end

  def ensure_replication_password!
    if replication_password.blank?
      self.replication_password = SecureRandom.alphanumeric(32)
      save!
    end
    replication_password
  end

  def get_replication_password
    primary? ? ensure_replication_password! : parent_node.ensure_replication_password!
  end

  def ensure_root_password!
    if root_password.blank?
      self.root_password = SecureRandom.alphanumeric(16)
      self.root_password = "password" if Rails.env.development?
      save!
    end
    root_password
  end

  def ensure_ssh_keys!
    if ssh_private_key.blank? || ssh_public_key.blank?
      require "sshkey"

      ssh_key = SSHKey.generate(type: "RSA", bits: 2048)
      self.ssh_private_key = ssh_key.private_key
      self.ssh_public_key = ssh_key.ssh_public_key
      save!
    end
    { private: ssh_private_key, public: ssh_public_key }
  end

  def ssh_private_key_path
    # Create a temporary file with the SSH private key
    require "tempfile"

    temp_file = Tempfile.new([ "ssh_key", ".pem" ])
    temp_file.write(ssh_private_key)
    temp_file.chmod(0600)
    temp_file.flush
    temp_file.close

    # Return the path - caller is responsible for cleanup
    temp_file.path
  end

  # All nodes are created with replica-ready PostgreSQL configuration by default.
  # This includes WAL level and archive settings.
  # Replication user and pg_hba.conf entries are only created when needed.

  def set_default_database_type_version
    return if database_type_version.present? || cluster.blank?

    # For replica nodes, use the same version as the parent node for compatibility
    if parent_node.present? && parent_node.database_type_version.present?
      self.database_type_version = parent_node.database_type_version
    else
      # For primary nodes, set to cluster's default version
      self.database_type_version = cluster.default_version
    end
  end

  def parent_node_must_be_primary
    if parent_node.present? && parent_node.parent_node.present?
      errors.add(:parent_node, "cannot be a replica node. Replicas can only be created from primary nodes.")
    end
  end

  def database_type_version_matches_cluster
    return unless database_type_version.present? && cluster.present?

    unless database_type_version.database_type == cluster.database_type
      errors.add(:database_type_version, "must match the cluster's database type (#{cluster.database_type_name})")
    end
  end

  def replica_version_matches_primary
    return unless replica? && parent_node.present? && database_type_version.present? && parent_node.database_type_version.present?

    unless database_type_version == parent_node.database_type_version
      errors.add(:database_type_version, "must match the primary node's version (#{parent_node.database_type_version.display_name}) for proper replication compatibility")
    end
  end

  def cleanup_parent_replication_config
    nil unless parent_node.present?

    # If this was the last replica, optionally clean up replication configuration
    # For now, we'll leave the replication user and password for future use
    # This could be extended to remove pg_hba.conf entries for this specific replica
  end

  private

  def ensure_ssh_keys_and_password
    ensure_ssh_keys!
    ensure_root_password!
  end
end
