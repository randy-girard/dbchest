class Node < ApplicationRecord
  belongs_to :cluster
  belongs_to :provider

  has_many :node_settings, dependent: :destroy
  accepts_nested_attributes_for :node_settings

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
end
