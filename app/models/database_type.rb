class DatabaseType < ApplicationRecord
  has_many :database_type_versions, dependent: :destroy
  has_many :clusters, dependent: :restrict_with_error
  has_many :nodes, through: :clusters

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores allowed" }

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  scope :active, -> { joins(:database_type_versions) }

  def default_version
    database_type_versions.find_by(is_default: true) || database_type_versions.first
  end

  def supports_logical_replication?
    # PostgreSQL supports logical replication from version 10+
    # MySQL supports it from version 8.0+
    # Can be extended for other database types
    case slug
    when "postgresql"
      database_type_versions.any? { |v| v.version.to_f >= 10.0 }
    when "mysql"
      database_type_versions.any? { |v| v.version.to_f >= 8.0 }
    else
      false
    end
  end

  def handler_available?
    DatabaseTypes::BaseDatabaseType.registry[slug].present?
  end

  def handler_class
    DatabaseTypes::BaseDatabaseType.registry[slug]
  end

  private

  def generate_slug
    self.slug = name.downcase.gsub(/[^a-z0-9]/, "_").gsub(/_+/, "_").gsub(/^_|_$/, "")
  end
end
