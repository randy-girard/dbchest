class Cluster < ApplicationRecord
  belongs_to :database_type
  has_many :nodes, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :database_type, presence: true

  delegate :name, :slug, to: :database_type, prefix: true
  delegate :database_type_versions, to: :database_type

  # Set default database type to PostgreSQL if not specified
  before_validation :set_default_database_type, on: :create

  def cluster_type
    database_type&.slug || "postgresql" # fallback for existing clusters
  end

  def available_versions
    database_type&.database_type_versions&.order(:version) || []
  end

  def default_version
    database_type&.default_version
  end

  def supports_mixed_versions?
    # Allow mixed versions only if the database type supports logical replication
    database_type&.supports_logical_replication? || false
  end

  private

  def set_default_database_type
    return if database_type.present?
    
    # Default to PostgreSQL
    self.database_type = DatabaseType.find_by(slug: 'postgresql') || DatabaseType.first
  end
end
