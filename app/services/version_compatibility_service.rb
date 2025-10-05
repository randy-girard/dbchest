# frozen_string_literal: true

# Service for managing database version compatibility with operating systems
class VersionCompatibilityService
  # PostgreSQL/Ubuntu version compatibility matrix
  POSTGRESQL_UBUNTU_COMPATIBILITY = {
    "20.04" => {
      codename: "focal",
      supported_versions: [ 12, 13, 14, 15 ],
      max_version: 15,
      repository: "http://apt-archive.postgresql.org/pub/repos/apt/"
    },
    "22.04" => {
      codename: "jammy",
      supported_versions: [ 12, 13, 14, 15, 16, 17 ],
      max_version: 17,
      repository: "http://apt.postgresql.org/pub/repos/apt/"
    },
    "24.04" => {
      codename: "noble",
      supported_versions: [ 12, 13, 14, 15, 16, 17 ],
      max_version: 17,
      repository: "http://apt.postgresql.org/pub/repos/apt/"
    }
  }.freeze

  # MySQL/Ubuntu version compatibility matrix
  MYSQL_UBUNTU_COMPATIBILITY = {
    "20.04" => {
      codename: "focal",
      supported_versions: [ "5.7", "8.0" ],
      default_version: "8.0"
    },
    "22.04" => {
      codename: "jammy",
      supported_versions: [ "8.0" ],
      default_version: "8.0"
    },
    "24.04" => {
      codename: "noble",
      supported_versions: [ "8.0" ],
      default_version: "8.0"
    }
  }.freeze

  class << self
    # Check if a PostgreSQL version is compatible with an Ubuntu version
    def postgresql_compatible?(pg_version, ubuntu_version)
      return true if ubuntu_version.nil? # Skip check if Ubuntu version not provided

      compatibility = POSTGRESQL_UBUNTU_COMPATIBILITY[ubuntu_version]
      return false unless compatibility

      major_version = extract_major_version(pg_version)
      compatibility[:supported_versions].include?(major_version)
    end

    # Check if a MySQL version is compatible with an Ubuntu version
    def mysql_compatible?(mysql_version, ubuntu_version)
      return true if ubuntu_version.nil?

      compatibility = MYSQL_UBUNTU_COMPATIBILITY[ubuntu_version]
      return false unless compatibility

      compatibility[:supported_versions].include?(mysql_version.to_s)
    end

    # Get compatibility info for a database version
    def compatibility_info(database_type, version, ubuntu_version = nil)
      case database_type.to_s.downcase
      when "postgresql"
        postgresql_compatibility_info(version, ubuntu_version)
      when "mysql"
        mysql_compatibility_info(version, ubuntu_version)
      else
        { compatible: true, notes: [] }
      end
    end

    # Get PostgreSQL repository URL based on version and Ubuntu version
    def postgresql_repository_url(pg_version, ubuntu_version = "22.04")
      compatibility = POSTGRESQL_UBUNTU_COMPATIBILITY[ubuntu_version]
      return nil unless compatibility

      major_version = extract_major_version(pg_version)

      # PostgreSQL 16+ uses main repository, older versions use archive
      if major_version >= 16
        "http://apt.postgresql.org/pub/repos/apt/"
      else
        "http://apt-archive.postgresql.org/pub/repos/apt/"
      end
    end

    # Get recommended PostgreSQL version for Ubuntu version
    def recommended_postgresql_version(ubuntu_version)
      compatibility = POSTGRESQL_UBUNTU_COMPATIBILITY[ubuntu_version]
      return 15 unless compatibility # Safe default

      compatibility[:max_version]
    end

    # Get all supported PostgreSQL versions for Ubuntu version
    def supported_postgresql_versions(ubuntu_version)
      compatibility = POSTGRESQL_UBUNTU_COMPATIBILITY[ubuntu_version]
      return [] unless compatibility

      compatibility[:supported_versions]
    end

    # Validate database type version compatibility
    def validate_compatibility!(database_type, version, ubuntu_version)
      info = compatibility_info(database_type, version, ubuntu_version)

      unless info[:compatible]
        raise VersionCompatibilityError, info[:error_message]
      end

      info
    end

    # Generate installation command with version-aware repository selection
    def generate_postgresql_install_command(version, ubuntu_version = nil)
      major_version = extract_major_version(version)

      # Check compatibility if Ubuntu version provided
      if ubuntu_version && !postgresql_compatible?(version, ubuntu_version)
        return generate_compatibility_error_command(version, ubuntu_version)
      end

      # Determine repository based on version
      repo_url = postgresql_repository_url(version, ubuntu_version || "22.04")

      <<~CMD.strip
        # PostgreSQL #{version} installation with version-aware repository
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb #{repo_url} $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-#{version} postgresql-contrib-#{version}
      CMD
    end

    private

    def extract_major_version(version)
      version.to_s.split(".").first.to_i
    end

    def postgresql_compatibility_info(version, ubuntu_version)
      return { compatible: true, notes: [] } if ubuntu_version.nil?

      major_version = extract_major_version(version)
      compatibility = POSTGRESQL_UBUNTU_COMPATIBILITY[ubuntu_version]

      unless compatibility
        return {
          compatible: false,
          notes: [ "Unknown Ubuntu version: #{ubuntu_version}" ],
          error_message: "Ubuntu version #{ubuntu_version} is not in the compatibility matrix"
        }
      end

      if compatibility[:supported_versions].include?(major_version)
        notes = []

        # Add informational notes
        if major_version >= 16
          notes << "PostgreSQL #{version} requires Ubuntu 22.04 or later"
        end

        {
          compatible: true,
          notes: notes,
          repository: postgresql_repository_url(version, ubuntu_version),
          ubuntu_codename: compatibility[:codename]
        }
      else
        {
          compatible: false,
          notes: [
            "PostgreSQL #{version} is not compatible with Ubuntu #{ubuntu_version}",
            "Supported versions for Ubuntu #{ubuntu_version}: #{compatibility[:supported_versions].join(', ')}"
          ],
          error_message: "PostgreSQL #{version} is not available for Ubuntu #{ubuntu_version}. " \
                        "Supported versions: #{compatibility[:supported_versions].join(', ')}"
        }
      end
    end

    def mysql_compatibility_info(version, ubuntu_version)
      return { compatible: true, notes: [] } if ubuntu_version.nil?

      compatibility = MYSQL_UBUNTU_COMPATIBILITY[ubuntu_version]

      unless compatibility
        return {
          compatible: false,
          notes: [ "Unknown Ubuntu version: #{ubuntu_version}" ],
          error_message: "Ubuntu version #{ubuntu_version} is not in the compatibility matrix"
        }
      end

      if compatibility[:supported_versions].include?(version.to_s)
        {
          compatible: true,
          notes: [],
          default_version: compatibility[:default_version]
        }
      else
        {
          compatible: false,
          notes: [
            "MySQL #{version} is not compatible with Ubuntu #{ubuntu_version}",
            "Supported versions for Ubuntu #{ubuntu_version}: #{compatibility[:supported_versions].join(', ')}"
          ],
          error_message: "MySQL #{version} is not available for Ubuntu #{ubuntu_version}. " \
                        "Supported versions: #{compatibility[:supported_versions].join(', ')}"
        }
      end
    end

    def generate_compatibility_error_command(version, ubuntu_version)
      compatibility = POSTGRESQL_UBUNTU_COMPATIBILITY[ubuntu_version]
      supported = compatibility ? compatibility[:supported_versions].join(", ") : "unknown"

      <<~CMD.strip
        # PostgreSQL #{version} compatibility check
        echo "ERROR: PostgreSQL #{version} is not compatible with Ubuntu #{ubuntu_version}"
        echo "Supported PostgreSQL versions for Ubuntu #{ubuntu_version}: #{supported}"
        echo "Please select a compatible PostgreSQL version or upgrade your Ubuntu version"
        exit 1
      CMD
    end
  end

  # Custom error class for version compatibility issues
  class VersionCompatibilityError < StandardError; end
end
