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
    version.split('.').first.to_i
  end

  def supports_logical_replication?
    case database_type.slug
    when 'postgresql'
      major_version >= 10
    when 'mysql'
      major_version >= 8
    else
      false
    end
  end

  def supports_streaming_replication?
    case database_type.slug
    when 'postgresql'
      major_version >= 9
    when 'mysql'
      major_version >= 5
    else
      false
    end
  end

  def replication_method_for_cross_version(target_version)
    # If versions are different and logical replication is supported, use logical
    # Otherwise use streaming if supported, else return nil (not supported)
    if version != target_version.version
      if supports_logical_replication? && target_version.supports_logical_replication?
        'logical'
      elsif supports_streaming_replication? && target_version.supports_streaming_replication?
        'streaming'
      else
        nil # Replication not supported between these versions
      end
    else
      # Same version, prefer streaming for better performance
      if supports_streaming_replication?
        'streaming'
      elsif supports_logical_replication?
        'logical'
      else
        nil
      end
    end
  end

  def compatibility_notes
    notes = []
    
    if database_type.slug == 'postgresql' && major_version >= 16
      notes << "PostgreSQL 16+ requires Ubuntu 22.04 or later. Will fail on Ubuntu 20.04."
    end
    
    notes
  end

  def ubuntu_compatible?(ubuntu_version = nil)
    return true unless database_type.slug == 'postgresql'
    
    # For PostgreSQL 16+, we know it's not available in Ubuntu 20.04 repositories
    if major_version >= 16
      return false if ubuntu_version&.start_with?('20.04')
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
