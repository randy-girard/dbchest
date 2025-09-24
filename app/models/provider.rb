require "proxmox_api"
require "ostruct"

class Provider < ApplicationRecord
  belongs_to :provider_type

  # FIXME: We need to make sure this doesn't happen
  has_many :nodes, dependent: :destroy

  has_many :provider_settings, dependent: :destroy
  accepts_nested_attributes_for :provider_settings

  validates :name, presence: true
  validate :provider_type_exists

  def build_provider_settings!
    provider_type.provider_type_options.each do |option|
      existing_setting = provider_settings.find { |ps| ps.key == option.key }
      unless existing_setting
        self.provider_settings.build(
          provider_type_option_id: option.id,
          label: option.label,
          key: option.key,
          value: "placeholder")
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
    ProviderClient::Base.for_provider(self)
  rescue ArgumentError => e
    Rails.logger.warn "Provider client not found: #{e.message}"
    nil
  end

  private

  def provider_type_exists
    return if provider_type_id.blank?

    unless ProviderType.exists?(provider_type_id)
      errors.add(:provider_type_id, "is not included in the list")
    end
  end
end
