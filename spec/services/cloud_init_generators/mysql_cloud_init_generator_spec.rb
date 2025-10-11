# frozen_string_literal: true

require "rails_helper"

RSpec.describe CloudInitGenerators::MysqlCloudInitGenerator do
  let(:database_type) { create(:database_type, name: "MySQL", slug: "mysql") }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: "8.0") }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:node) { create(:node, cluster: cluster, database_type_version: database_type_version) }
  let(:database_type_handler) { DatabaseTypes::MysqlDatabaseType.new(database_type_version) }
  let(:generator) { described_class.new(database_type_handler, node) }

  describe "#generate" do
    context "for primary node" do
      let(:script) { generator.generate(is_replica: false) }

      it "generates a valid bash script" do
        expect(script).to start_with("#!/bin/bash")
        expect(script).to include("set -e")
      end

      it "includes all required modules" do
        expect(script).to include("cat > /tmp/common.sh")
        expect(script).to include("cat > /tmp/version_compatibility.sh")
        expect(script).to include("cat > /tmp/mysql.sh")
      end

      it "makes modules executable" do
        expect(script).to include("chmod +x /tmp/common.sh")
        expect(script).to include("chmod +x /tmp/version_compatibility.sh")
        expect(script).to include("chmod +x /tmp/mysql.sh")
      end

      it "sources the common module" do
        expect(script).to include("source /tmp/common.sh")
      end

      it "sources the version compatibility module" do
        expect(script).to include("source /tmp/version_compatibility.sh")
      end

      it "sources the mysql module" do
        expect(script).to include("source /tmp/mysql.sh")
      end

      it "includes version compatibility functions" do
        expect(script).to include("detect_ubuntu_version")
        expect(script).to include("validate_database_version")
      end

      it "includes common functions" do
        expect(script).to include("check_root")
        expect(script).to include("log")
        expect(script).to include("callback")
      end

      it "includes MySQL installation" do
        expect(script).to include("install_mysql")
      end

      it "substitutes database version" do
        expect(script).to include(database_type_version.version)
      end

      it "substitutes service name" do
        expect(script).to include(database_type_version.service_name)
      end

      it "substitutes callback URL" do
        # The callback URL is in the format: http://localhost:3000/nodes/{id}/status_callback
        expect(script).to include("/nodes/#{node.id}/status_callback")
      end

      it "substitutes root password" do
        expect(script).to include(node.root_password)
      end

      it "does not include PRIMARY_HOST for primary nodes" do
        # PRIMARY_HOST should be empty for primary nodes
        expect(script).not_to match(/PRIMARY_HOST=.+/)
      end

      it "includes display_compatibility_matrix call" do
        expect(script).to include("display_compatibility_matrix")
      end

      it "includes configure_mysql_primary call" do
        expect(script).to include("configure_mysql_primary")
      end
    end

    context "for replica node" do
      let(:primary_node) { create(:node, cluster: cluster, database_type_version: database_type_version, status: "active") }
      let(:replica_node) { create(:node, cluster: cluster, database_type_version: database_type_version, parent_node: primary_node) }
      let(:replica_generator) { described_class.new(database_type_handler, replica_node) }
      let(:script) { replica_generator.generate(is_replica: true) }

      before do
        # Set up primary node with IP address
        primary_node.runtime_config = { "ip_address" => "10.0.0.1" }
        primary_node.save!
        primary_node.ensure_replication_password!
      end

      it "generates a valid bash script" do
        expect(script).to start_with("#!/bin/bash")
        expect(script).to include("set -e")
      end

      it "includes all required modules" do
        expect(script).to include("cat > /tmp/common.sh")
        expect(script).to include("cat > /tmp/version_compatibility.sh")
        expect(script).to include("cat > /tmp/mysql.sh")
      end

      it "includes MySQL replica setup" do
        expect(script).to include("setup_mysql_replica")
      end

      it "substitutes primary host IP" do
        expect(script).to include("10.0.0.1")
      end

      it "substitutes replication password" do
        expect(script).to include(primary_node.replication_password)
      end

      it "includes GTID configuration" do
        expect(script).to include("gtid-mode")
        expect(script).to include("MASTER_AUTO_POSITION")
      end

      it "includes replica configuration" do
        expect(script).to include("read-only")
        expect(script).to include("relay-log")
      end
    end
  end

  describe "template substitution" do
    let(:script) { generator.generate(is_replica: false) }

    it "substitutes DB_VERSION" do
      expect(script).to include("MySQL version: #{database_type_version.version}")
    end

    it "substitutes SERVICE_NAME" do
      expect(script).to include("Service name: #{database_type_version.service_name}")
    end

    it "substitutes ROOT_PASSWORD" do
      expect(script).to include(node.root_password)
    end

    it "substitutes CALLBACK_URL" do
      expect(script).to include("/nodes/#{node.id}/status_callback")
    end

    it "substitutes INSTALL_COMMAND" do
      expect(script).to include(database_type_version.install_command)
    end
  end

  describe "error handling" do
    let(:script) { generator.generate(is_replica: false) }

    it "includes fail-fast error handling" do
      expect(script).to include("set -e")
      expect(script).to include("setup_error_handling")
    end

    it "includes error callback on failure" do
      expect(script).to include('callback "error"')
    end
  end
end
