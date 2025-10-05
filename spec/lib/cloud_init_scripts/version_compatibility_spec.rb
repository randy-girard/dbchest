# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cloud Init Version Compatibility Module" do
  let(:module_path) { Rails.root.join("lib", "cloud_init_scripts", "modules", "version_compatibility.sh") }
  let(:module_content) { File.read(module_path) }

  describe "module structure" do
    it "exists" do
      expect(File.exist?(module_path)).to be true
    end

    it "has bash shebang" do
      expect(module_content).to start_with("#!/bin/bash")
    end

    it "has proper header comment" do
      expect(module_content).to include("DBChest Cloud Init - Version Compatibility Module")
    end
  end

  describe "required functions" do
    it "defines detect_ubuntu_version function" do
      expect(module_content).to include("detect_ubuntu_version()")
    end

    it "defines detect_ubuntu_codename function" do
      expect(module_content).to include("detect_ubuntu_codename()")
    end

    it "defines check_postgresql_ubuntu_compatibility function" do
      expect(module_content).to include("check_postgresql_ubuntu_compatibility()")
    end

    it "defines get_postgresql_apt_repo function" do
      expect(module_content).to include("get_postgresql_apt_repo()")
    end

    it "defines validate_database_version function" do
      expect(module_content).to include("validate_database_version()")
    end

    it "defines display_compatibility_matrix function" do
      expect(module_content).to include("display_compatibility_matrix()")
    end

    it "defines check_package_availability function" do
      expect(module_content).to include("check_package_availability()")
    end

    it "defines get_recommended_postgresql_version function" do
      expect(module_content).to include("get_recommended_postgresql_version()")
    end

    it "defines install_postgresql_version_aware function" do
      expect(module_content).to include("install_postgresql_version_aware()")
    end
  end

  describe "version compatibility logic" do
    it "checks for PostgreSQL 16+ incompatibility with Ubuntu 20.04" do
      expect(module_content).to include("focal")
      expect(module_content).to match(/pg_major_version.*-ge.*16/)
    end

    it "includes compatibility matrix information" do
      expect(module_content).to include("Ubuntu 20.04")
      expect(module_content).to include("Ubuntu 22.04")
      expect(module_content).to include("PostgreSQL")
    end

    it "includes repository URL selection logic" do
      expect(module_content).to include("apt.postgresql.org")
      # All versions now use the main repository
      expect(module_content).to include("main repository contains all versions")
    end
  end

  describe "error handling" do
    it "includes error messages for incompatible versions" do
      expect(module_content).to include("ERROR")
      expect(module_content).to include("not compatible")
    end

    it "includes callback for error reporting" do
      expect(module_content).to include("callback")
    end

    it "includes exit on error" do
      expect(module_content).to include("return 1")
    end
  end

  describe "logging" do
    it "includes log function calls" do
      expect(module_content).to include("log")
    end

    it "logs version detection" do
      expect(module_content).to match(/log.*Detected.*Ubuntu/)
    end

    it "logs compatibility checks" do
      expect(module_content).to match(/log.*Checking.*compatibility/)
    end
  end

  describe "Ubuntu version detection" do
    it "uses lsb_release for version detection" do
      expect(module_content).to include("lsb_release -rs")
    end

    it "uses lsb_release for codename detection" do
      expect(module_content).to include("lsb_release -cs")
    end
  end

  describe "PostgreSQL repository selection" do
    it "uses main repository for all PostgreSQL versions" do
      # All versions (12-17) now use the main repository
      expect(module_content).to include("apt.postgresql.org")
      expect(module_content).to include("All PostgreSQL versions use the main repository")
    end

    it "includes repository selection function" do
      expect(module_content).to include("get_postgresql_apt_repo")
    end
  end

  describe "compatibility matrix" do
    it "documents Ubuntu 20.04 supported versions" do
      expect(module_content).to match(/20\.04.*12.*13.*14.*15/)
    end

    it "documents Ubuntu 22.04 supported versions" do
      expect(module_content).to match(/22\.04.*16.*17/)
    end
  end

  describe "package availability checking" do
    it "uses apt-cache to check package availability" do
      expect(module_content).to include("apt-cache show")
    end

    it "updates package cache before checking" do
      expect(module_content).to include("apt-get update")
    end
  end

  describe "recommended version logic" do
    it "recommends PostgreSQL 15 for Ubuntu 20.04" do
      expect(module_content).to match(/focal.*15/)
    end

    it "recommends PostgreSQL 17 for Ubuntu 22.04" do
      expect(module_content).to match(/jammy.*17/)
    end
  end

  describe "version-aware installation" do
    it "validates before installation" do
      # install_postgresql_version_aware should call validate_database_version
      install_function = module_content[/install_postgresql_version_aware\(\).*?^}/m]
      expect(install_function).to include("validate_database_version")
    end

    it "adds PostgreSQL APT key" do
      expect(module_content).to include("apt-key add")
      expect(module_content).to include("postgresql.org/media/keys")
    end

    it "adds repository to sources list" do
      expect(module_content).to include("/etc/apt/sources.list.d/pgdg.list")
    end

    it "installs PostgreSQL packages" do
      expect(module_content).to include("apt-get install")
      expect(module_content).to include("postgresql-")
    end
  end

  describe "syntax validation" do
    it "has valid bash syntax" do
      # Use bash -n to check syntax without executing
      result = system("bash", "-n", module_path.to_s)
      expect(result).to be(true), "Bash syntax check failed for version_compatibility.sh"
    end
  end

  describe "integration with other modules" do
    it "uses log function from common module" do
      expect(module_content).to include('log "')
    end

    it "uses callback function from common module" do
      expect(module_content).to include('callback "')
    end
  end
end
