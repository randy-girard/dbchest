class ProviderType < ApplicationRecord
  has_many :providers
  has_many :provider_type_options
  has_many :provider_type_node_options

  validates :name, presence: true
end
