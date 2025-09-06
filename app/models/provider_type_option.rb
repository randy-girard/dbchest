class ProviderTypeOption < ApplicationRecord
  belongs_to :provider_type

  has_many :provider_settings
end
