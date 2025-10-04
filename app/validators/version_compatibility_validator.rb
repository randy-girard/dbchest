# frozen_string_literal: true

# Validator for checking database version compatibility with OS versions
class VersionCompatibilityValidator < ActiveModel::Validator
  def validate(record)
    return unless record.database_type_version.present?
    return unless record.respond_to?(:ubuntu_version) && record.ubuntu_version.present?

    database_type = record.database_type_version.database_type.slug
    version = record.database_type_version.version
    ubuntu_version = record.ubuntu_version

    compatibility_info = VersionCompatibilityService.compatibility_info(
      database_type,
      version,
      ubuntu_version
    )

    unless compatibility_info[:compatible]
      record.errors.add(
        :database_type_version,
        compatibility_info[:error_message] || "is not compatible with Ubuntu #{ubuntu_version}"
      )
      
      # Add detailed notes as additional errors
      compatibility_info[:notes]&.each do |note|
        record.errors.add(:base, note)
      end
    end
  end
end

