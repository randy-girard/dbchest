require_relative "../services/database_types/base_database_type"

class DatabaseTypeVersion < ApplicationRecord
  belongs_to :database_type
  has_many :nodes, dependent: :restrict_with_error

  validates :version, presence: true, uniqueness: { scope: :database_type_id }
  validates :install_command, presence: true
  validates :default_port, presence: true, numericality: { greater_than: 0 }
  validates :service_name, presence: true

  before_save :ensure_single_default, if: :is_default?

  scope :defaults, -> { where(is_default: true) }
  scope :for_database_type, ->(type) { joins(:database_type).where(database_type: { slug: type }) }

  def display_name
    "#{database_type.name} #{version}"
  end

  def major_version
    version.split(".").first.to_i
  end

  def supports_logical_replication?
    database_type_handler.supports_logical_replication?
  end

  def supports_streaming_replication?
    database_type_handler.supports_streaming_replication?
  end

  def replication_method_for_cross_version(target_version)
    return nil unless target_version.is_a?(DatabaseTypeVersion)
    return nil unless target_version.database_type_id == database_type_id

    database_type_handler.replication_method_for_cross_version(target_version)
  end

  def database_type_handler
    @database_type_handler ||= DatabaseTypes::BaseDatabaseType.for_database_type_version(self)
  end

  def compatibility_notes
    notes = []

    if database_type.slug == "postgresql" && major_version >= 16
      notes << "PostgreSQL 16+ requires Ubuntu 22.04 or later. Will fail on Ubuntu 20.04."
    end

    notes
  end

  def ubuntu_compatible?(ubuntu_version = nil)
    return true unless database_type.slug == "postgresql"

    # For PostgreSQL 16+, we know it's not available in Ubuntu 20.04 repositories
    if major_version >= 16
      return false if ubuntu_version&.start_with?("20.04")
    end

    true
  end

  private

  def ensure_single_default
    if is_default_changed? && is_default?
      DatabaseTypeVersion.where(database_type: database_type).where.not(id: id).update_all(is_default: false)
    end
  end
end
