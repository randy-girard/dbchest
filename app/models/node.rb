class Node < ApplicationRecord
  belongs_to :cluster
  belongs_to :provider
  belongs_to :parent_node, class_name: "Node", optional: true

  has_many :credentials, dependent: :destroy
  has_many :node_settings, dependent: :destroy
  has_many :replicas, class_name: "Node", foreign_key: "parent_node_id", dependent: :destroy
  accepts_nested_attributes_for :node_settings

  validates :name, presence: true, uniqueness: { scope: :cluster_id }
  validate :parent_node_must_be_primary

  after_destroy :cleanup_parent_replication_config, if: :replica?

  encrypts :terraform_state,
           :ssh_public_key,
           :ssh_private_key,
           :runtime_config,
           :replication_password

  def build_node_settings!
    provider.provider_type.provider_type_node_options.each do |option|
      unless node_settings.exists?(key: option.key)
        self.node_settings.build(
          provider_type_node_option_id: option.id,
          key: option.key)
      end
    end
  end

  def get_runtime_config_value(key)
    runtime_config.fetch(key, {}).fetch("value", nil)
  end

  def get_ip_address
    ip_with_subnet = get_runtime_config_value("ip_address")
    return nil if ip_with_subnet.nil?
    
    # Use IPAddr to properly handle IP with or without subnet notation
    IPAddr.new(ip_with_subnet).to_s
  rescue IPAddr::InvalidAddressError
    # Fallback to simple string splitting if IPAddr fails
    ip_with_subnet.split('/').first
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

  def provision_replica!
    CreateService.perform_async(id, true)
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

  # All nodes are created with replica-ready PostgreSQL configuration by default.
  # This includes WAL level and archive settings.
  # Replication user and pg_hba.conf entries are only created when needed.

  private

  def parent_node_must_be_primary
    if parent_node.present? && parent_node.parent_node.present?
      errors.add(:parent_node, "cannot be a replica node. Replicas can only be created from primary nodes.")
    end
  end

  def cleanup_parent_replication_config
    return unless parent_node.present?
    
    # If this was the last replica, optionally clean up replication configuration
    # For now, we'll leave the replication user and password for future use
    # This could be extended to remove pg_hba.conf entries for this specific replica
  end
end
