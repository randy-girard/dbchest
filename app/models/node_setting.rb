class NodeSetting < ApplicationRecord
  belongs_to :node
  belongs_to :provider_type_node_option

  validates :key, uniqueness: { scope: [:node, :provider_type_node_option] }

  validates :value, presence: true, if: ->(record) { record.provider_type_node_option.required? }
end
