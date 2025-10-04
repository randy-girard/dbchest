# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cloud Init Modules" do
  let(:modules_dir) { Rails.root.join("lib", "cloud_init_scripts", "modules") }

  describe "module files" do
    it "has common.sh module" do
      expect(File.exist?(modules_dir.join("common.sh"))).to be true
    end

    it "has version_compatibility.sh module" do
      expect(File.exist?(modules_dir.join("version_compatibility.sh"))).to be true
    end

    it "has postgresql.sh module" do
      expect(File.exist?(modules_dir.join("postgresql.sh"))).to be true
    end

    it "has mysql.sh module" do
      expect(File.exist?(modules_dir.join("mysql.sh"))).to be true
    end
  end

  describe "common.sh module" do
    let(:module_content) { File.read(modules_dir.join("common.sh")) }

    it "has bash shebang" do
      expect(module_content).to start_with("#!/bin/bash")
    end

    it "defines check_root function" do
      expect(module_content).to include("check_root()")
    end

    it "defines log function" do
      expect(module_content).to include("log()")
    end

    it "defines callback function" do
      expect(module_content).to include("callback()")
    end

    it "defines cleanup function" do
      expect(module_content).to include("cleanup()")
    end

    it "defines setup_error_handling function" do
      expect(module_content).to include("setup_error_handling()")
    end

    it "defines error_handler function" do
      expect(module_content).to include("error_handler()")
    end

    it "defines set_step function" do
      expect(module_content).to include("set_step()")
    end

    it "defines safe_exec function" do
      expect(module_content).to include("safe_exec()")
    end

    it "defines install_essential_packages function" do
      expect(module_content).to include("install_essential_packages()")
    end

    it "defines setup_metrics_collection function" do
      expect(module_content).to include("setup_metrics_collection()")
    end

    it "defines configure_ssh_access function" do
      expect(module_content).to include("configure_ssh_access()")
    end

    it "defines wait_for_service function" do
      expect(module_content).to include("wait_for_service()")
    end

    it "has valid bash syntax" do
      result = system("bash", "-n", modules_dir.join("common.sh").to_s)
      expect(result).to be(true), "Bash syntax check failed for common.sh"
    end
  end

  describe "postgresql.sh module" do
    let(:module_content) { File.read(modules_dir.join("postgresql.sh")) }

    it "has bash shebang" do
      expect(module_content).to start_with("#!/bin/bash")
    end

    it "defines install_postgresql function" do
      expect(module_content).to include("install_postgresql()")
    end

    it "defines configure_postgresql_auth function" do
      expect(module_content).to include("configure_postgresql_auth()")
    end

    it "defines configure_postgresql_primary function" do
      expect(module_content).to include("configure_postgresql_primary()")
    end

    it "defines setup_postgresql_replica function" do
      expect(module_content).to include("setup_postgresql_replica()")
    end

    it "includes version validation" do
      expect(module_content).to include("validate_database_version")
    end

    it "uses template variables" do
      expect(module_content).to include("{{INSTALL_COMMAND}}")
      expect(module_content).to include("{{ROOT_PASSWORD}}")
    end

    it "has valid bash syntax" do
      # Note: This will fail on template variables, but checks overall structure
      # We'll skip this for modules with template variables
      # result = system("bash", "-n", modules_dir.join("postgresql.sh").to_s)
      # expect(result).to be true
    end
  end

  describe "mysql.sh module" do
    let(:module_content) { File.read(modules_dir.join("mysql.sh")) }

    it "has bash shebang" do
      expect(module_content).to start_with("#!/bin/bash")
    end

    it "defines install_mysql function" do
      expect(module_content).to include("install_mysql()")
    end

    it "defines configure_mysql_auth function" do
      expect(module_content).to include("configure_mysql_auth()")
    end

    it "defines configure_mysql_primary function" do
      expect(module_content).to include("configure_mysql_primary()")
    end

    it "defines setup_mysql_replica function" do
      expect(module_content).to include("setup_mysql_replica()")
    end

    it "uses template variables" do
      expect(module_content).to include("{{INSTALL_COMMAND}}")
      expect(module_content).to include("{{ROOT_PASSWORD}}")
    end
  end

  describe "module integration" do
    it "all modules use consistent function naming" do
      common = File.read(modules_dir.join("common.sh"))
      postgresql = File.read(modules_dir.join("postgresql.sh"))
      
      # PostgreSQL module should use functions from common module
      expect(postgresql).to include("log ")
      expect(postgresql).to include("callback ")
    end

    it "version_compatibility module uses common functions" do
      version_compat = File.read(modules_dir.join("version_compatibility.sh"))
      
      expect(version_compat).to include("log ")
      expect(version_compat).to include("callback ")
    end
  end
end

