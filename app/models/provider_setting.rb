class ProviderSetting < ApplicationRecord
  belongs_to :provider
  belongs_to :provider_type_option

  encrypts :key
  encrypts :value

  validates :key, :value, presence: true

  attr_accessor :label
end
