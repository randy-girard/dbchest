# frozen_string_literal: true

# Concern for populating replica node settings from parent node
module ReplicaSettingsPopulator
  extend ActiveSupport::Concern

  # Network-related settings that should not be copied from parent to replica
  NETWORK_SETTINGS = %w[ip_address gateway network subnet cidr].freeze

  private

  # Populate replica node settings from parent node, excluding network settings
  def populate_replica_settings_from_parent(replica, parent_node)
    replica.build_node_settings! if replica.node_settings.empty?

    parent_node.node_settings.includes(:provider_type_node_option).each do |parent_setting|
      next if NETWORK_SETTINGS.include?(parent_setting.key)

      replica_setting = replica.node_settings.find { |rs| rs.key == parent_setting.key }
      replica_setting.value = parent_setting.value if replica_setting
    end
  end
end

