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

  encrypts :terraform_state,
           :ssh_public_key,
           :ssh_private_key,
           :runtime_config

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
    CreateService.perform_async(id, replica: true)
  end

  private

  def parent_node_must_be_primary
    if parent_node.present? && parent_node.parent_node.present?
      errors.add(:parent_node, "cannot be a replica node. Replicas can only be created from primary nodes.")
    end
  end
end
