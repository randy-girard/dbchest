require "proxmox_api"
require "ostruct"

class Provider < ApplicationRecord
  belongs_to :provider_type

  # FIXME: We need to make sure this doesn't happen
  has_many :nodes, dependent: :destroy

  has_many :provider_settings, dependent: :destroy
  accepts_nested_attributes_for :provider_settings

  validates :name, presence: true
  validates :provider_type_id, inclusion: { in: ProviderType.pluck(:id) }

  def build_provider_settings!
    provider_type.provider_type_options.each do |option|
      unless provider_settings.exists?(key: option.key)
        self.provider_settings.build(
          provider_type_option_id: option.id,
          label: option.label,
          key: option.key)
      end
    end
  end

  def provider_settings_object
    hash = {}
    provider_type.provider_type_options.each do |option|
      hash[option.key] = provider_settings.where(provider_type_option_id: option.id).first.value
    end
    OpenStruct.new(hash)
  end

  def terraform_vars
    vars = {}
    provider_settings.each do |ps|
      vars[ps.key] = ps.value
    end
    vars
  end

  def api_client
    case provider_type.key
    when "proxmox"
      ProviderClient::Proxmox.new(provider_settings_object)
    end
  end
end
