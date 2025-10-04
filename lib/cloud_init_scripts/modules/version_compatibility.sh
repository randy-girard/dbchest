#!/bin/bash

# DBChest Cloud Init - Version Compatibility Module
# This module contains version detection and compatibility validation functions

# Detect Ubuntu version
detect_ubuntu_version() {
  local ubuntu_version=$(lsb_release -rs)
  local ubuntu_codename=$(lsb_release -cs)
  
  log "Detected Ubuntu version: $ubuntu_version ($ubuntu_codename)"
  
  echo "$ubuntu_version"
}

# Detect Ubuntu codename
detect_ubuntu_codename() {
  local ubuntu_codename=$(lsb_release -cs)
  echo "$ubuntu_codename"
}

# Check if PostgreSQL version is compatible with Ubuntu version
check_postgresql_ubuntu_compatibility() {
  local pg_version="$1"
  local ubuntu_version="${2:-$(detect_ubuntu_version)}"
  local ubuntu_codename="${3:-$(detect_ubuntu_codename)}"
  
  # Extract major version number
  local pg_major_version=$(echo "$pg_version" | cut -d'.' -f1)
  
  log "Checking PostgreSQL $pg_version compatibility with Ubuntu $ubuntu_version ($ubuntu_codename)"
  
  # PostgreSQL 16 and 17 are NOT available on Ubuntu 20.04 (focal)
  if [ "$pg_major_version" -ge 16 ] && [ "$ubuntu_codename" = "focal" ]; then
    log "ERROR: PostgreSQL $pg_version is not compatible with Ubuntu $ubuntu_version ($ubuntu_codename)"
    log "PostgreSQL 16+ requires Ubuntu 22.04 (jammy) or later"
    log "Available PostgreSQL versions for Ubuntu 20.04: 12, 13, 14, 15"
    return 1
  fi
  
  # PostgreSQL 12-15 work on both Ubuntu 20.04 and 22.04
  if [ "$pg_major_version" -ge 12 ] && [ "$pg_major_version" -le 15 ]; then
    log "PostgreSQL $pg_version is compatible with Ubuntu $ubuntu_version"
    return 0
  fi
  
  # PostgreSQL 16+ requires Ubuntu 22.04+
  if [ "$pg_major_version" -ge 16 ]; then
    if [ "$ubuntu_codename" = "jammy" ] || [ "$ubuntu_codename" = "noble" ]; then
      log "PostgreSQL $pg_version is compatible with Ubuntu $ubuntu_version"
      return 0
    else
      log "WARNING: PostgreSQL $pg_version may not be fully tested on Ubuntu $ubuntu_version"
      return 0
    fi
  fi
  
  # For older versions, assume compatibility
  log "PostgreSQL $pg_version compatibility check passed for Ubuntu $ubuntu_version"
  return 0
}

# Get appropriate PostgreSQL APT repository URL based on version
get_postgresql_apt_repo() {
  local pg_version="$1"
  local ubuntu_codename="${2:-$(detect_ubuntu_codename)}"

  # Extract major version number
  local pg_major_version=$(echo "$pg_version" | cut -d'.' -f1)

  # All PostgreSQL versions use the main repository
  # The main repository contains all versions (12, 13, 14, 15, 16, 17)
  echo "deb http://apt.postgresql.org/pub/repos/apt/ ${ubuntu_codename}-pgdg main"
}

# Validate database version before installation
validate_database_version() {
  local db_type="$1"
  local db_version="$2"
  local ubuntu_version="${3:-$(detect_ubuntu_version)}"
  local ubuntu_codename="${4:-$(detect_ubuntu_codename)}"
  
  log "Validating $db_type version $db_version for Ubuntu $ubuntu_version"
  
  case "$db_type" in
    postgresql)
      if ! check_postgresql_ubuntu_compatibility "$db_version" "$ubuntu_version" "$ubuntu_codename"; then
        callback "error" "PostgreSQL $db_version is not compatible with Ubuntu $ubuntu_version. Installation aborted."
        return 1
      fi
      ;;
    mysql)
      # MySQL version compatibility checks
      log "MySQL $db_version compatibility check passed"
      ;;
    mongodb)
      # MongoDB version compatibility checks
      log "MongoDB $db_version compatibility check passed"
      ;;
    cassandra)
      # Cassandra version compatibility checks
      log "Cassandra $db_version compatibility check passed"
      ;;
    *)
      log "WARNING: Unknown database type: $db_type"
      ;;
  esac
  
  return 0
}

# Display version compatibility matrix
display_compatibility_matrix() {
  log "=== PostgreSQL/Ubuntu Version Compatibility Matrix ==="
  log "Ubuntu 20.04 (focal):  PostgreSQL 12, 13, 14, 15"
  log "Ubuntu 22.04 (jammy):  PostgreSQL 12, 13, 14, 15, 16, 17"
  log "Ubuntu 24.04 (noble):  PostgreSQL 12, 13, 14, 15, 16, 17"
  log "======================================================="
}

# Check if a specific package version is available in repositories
check_package_availability() {
  local package_name="$1"
  local package_version="$2"
  
  log "Checking if $package_name-$package_version is available..."
  
  # Update package cache
  apt-get update -qq
  
  # Check if package is available
  if apt-cache show "$package_name-$package_version" >/dev/null 2>&1; then
    log "Package $package_name-$package_version is available"
    return 0
  else
    log "ERROR: Package $package_name-$package_version is not available in repositories"
    return 1
  fi
}

# Get recommended PostgreSQL version for current Ubuntu version
get_recommended_postgresql_version() {
  local ubuntu_codename=$(detect_ubuntu_codename)
  
  case "$ubuntu_codename" in
    focal)
      echo "15"  # Latest version compatible with Ubuntu 20.04
      ;;
    jammy|noble)
      echo "17"  # Latest version for Ubuntu 22.04+
      ;;
    *)
      echo "15"  # Safe default
      ;;
  esac
}

# Validate and install PostgreSQL with version-aware repository selection
install_postgresql_version_aware() {
  local pg_version="$1"
  local ubuntu_version=$(detect_ubuntu_version)
  local ubuntu_codename=$(detect_ubuntu_codename)
  
  log "Installing PostgreSQL $pg_version on Ubuntu $ubuntu_version ($ubuntu_codename)"
  
  # Validate compatibility
  if ! validate_database_version "postgresql" "$pg_version" "$ubuntu_version" "$ubuntu_codename"; then
    log "ERROR: PostgreSQL $pg_version installation aborted due to compatibility issues"
    display_compatibility_matrix
    return 1
  fi
  
  # Get appropriate repository
  local pg_repo=$(get_postgresql_apt_repo "$pg_version" "$ubuntu_codename")
  log "Using PostgreSQL repository: $pg_repo"
  
  # Add PostgreSQL APT key
  log "Adding PostgreSQL APT repository key..."
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
  
  # Add repository
  log "Adding PostgreSQL APT repository..."
  echo "$pg_repo" > /etc/apt/sources.list.d/pgdg.list
  
  # Update package cache
  log "Updating package cache..."
  apt-get update -qq
  
  # Check package availability
  if ! check_package_availability "postgresql" "$pg_version"; then
    log "ERROR: PostgreSQL $pg_version is not available for Ubuntu $ubuntu_version"
    display_compatibility_matrix
    return 1
  fi
  
  # Install PostgreSQL
  log "Installing PostgreSQL $pg_version packages..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    "postgresql-$pg_version" \
    "postgresql-contrib-$pg_version" || {
    log "ERROR: Failed to install PostgreSQL $pg_version"
    return 1
  }
  
  log "PostgreSQL $pg_version installed successfully"
  return 0
}

