# frozen_string_literal: true

require "rails_helper"

RSpec.describe CloudInitGenerators::PostgresqlCloudInitGenerator do
  let(:database_type) { create(:database_type, name: "PostgreSQL", slug: "postgresql") }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: "15") }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:node) { create(:node, cluster: cluster, database_type_version: database_type_version) }
  let(:database_type_handler) { DatabaseTypes::PostgresqlDatabaseType.new(database_type_version) }
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
        expect(script).to include("cat > /tmp/postgresql.sh")
      end

      it "makes modules executable" do
        expect(script).to include("chmod +x /tmp/common.sh")
        expect(script).to include("chmod +x /tmp/version_compatibility.sh")
        expect(script).to include("chmod +x /tmp/postgresql.sh")
      end

      it "sources the common module" do
        expect(script).to include("source /tmp/common.sh")
      end

      it "sources the version compatibility module" do
        expect(script).to include("source /tmp/version_compatibility.sh")
      end

      it "sources the postgresql module" do
        expect(script).to include("source /tmp/postgresql.sh")
      end

      it "includes version compatibility functions" do
        expect(script).to include("detect_ubuntu_version")
        expect(script).to include("check_postgresql_ubuntu_compatibility")
        expect(script).to include("validate_database_version")
      end

      it "includes common functions" do
        expect(script).to include("check_root")
        expect(script).to include("log")
        expect(script).to include("callback")
      end

      it "includes PostgreSQL installation" do
        expect(script).to include("install_postgresql")
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
    end

    context "for replica node" do
      let(:primary_node) { create(:node, cluster: cluster, database_type_version: database_type_version, status: "active") }
      let(:replica_node) { create(:node, cluster: cluster, database_type_version: database_type_version, parent_node: primary_node) }
      let(:replica_generator) { described_class.new(database_type_handler, replica_node) }
      let(:script) { replica_generator.generate(is_replica: true) }

      before do
        # Set up primary node with IP address - use hash, not JSON string
        primary_node.runtime_config = { "ip_address" => "10.0.0.1" }
        primary_node.save!
        primary_node.ensure_replication_password!
      end

      it "generates a valid bash script" do
        expect(script).to start_with("#!/bin/bash")
      end

      it "includes PRIMARY_HOST with parent node IP" do
        expect(script).to include("10.0.0.1")
      end

      it "includes replication password" do
        expect(script).to include(primary_node.replication_password)
      end

      it "includes replica setup function" do
        expect(script).to include("setup_postgresql_replica")
      end
    end

    context "version compatibility validation" do
      it "includes version validation before installation" do
        script = generator.generate(is_replica: false)
        expect(script).to include("validate_database_version")
      end

      it "includes compatibility matrix display" do
        script = generator.generate(is_replica: false)
        expect(script).to include("display_compatibility_matrix")
      end
    end
  end

  describe "script structure" do
    let(:script) { generator.generate(is_replica: false) }

    it "has proper module embedding" do
      # Check that modules are embedded as heredocs
      expect(script).to match(/cat > \/tmp\/common\.sh << 'COMMON_MODULE_EOF'/)
      expect(script).to match(/cat > \/tmp\/version_compatibility\.sh << 'VERSION_COMPATIBILITY_MODULE_EOF'/)
      expect(script).to match(/cat > \/tmp\/postgresql\.sh << 'DATABASE_MODULE_EOF'/)
    end

    it "has proper module termination" do
      expect(script).to include("COMMON_MODULE_EOF")
      expect(script).to include("VERSION_COMPATIBILITY_MODULE_EOF")
      expect(script).to include("DATABASE_MODULE_EOF")
    end

    it "sources modules in correct order" do
      common_index = script.index("source /tmp/common.sh")
      version_index = script.index("source /tmp/version_compatibility.sh")
      postgresql_index = script.index("source /tmp/postgresql.sh")

      expect(common_index).to be < version_index
      expect(version_index).to be < postgresql_index
    end
  end

  describe "variable substitution" do
    let(:script) { generator.generate(is_replica: false) }

    it "does not contain unsubstituted template variables" do
      expect(script).not_to include("{{DB_VERSION}}")
      expect(script).not_to include("{{SERVICE_NAME}}")
      expect(script).not_to include("{{CALLBACK_URL}}")
      expect(script).not_to include("{{ROOT_PASSWORD}}")
    end

    it "substitutes install command" do
      expect(script).to include(database_type_version.install_command) if database_type_version.install_command.present?
    end
  end

  describe "error handling" do
    it "includes error handling with set -e" do
      script = generator.generate(is_replica: false)
      expect(script).to include("set -e")
    end

    it "includes comprehensive error handling" do
      script = generator.generate(is_replica: false)
      expect(script).to include("setup_error_handling")
    end

    it "includes error handler function" do
      script = generator.generate(is_replica: false)
      expect(script).to include("error_handler")
    end
  end

  describe "metrics collection" do
    let(:script) { generator.generate(is_replica: false) }

    it "includes metrics setup" do
      expect(script).to include("setup_metrics_collection")
    end

    it "includes metrics API key" do
      expect(script).to include(node.metrics_api_key) if node.metrics_api_key.present?
    end
  end

  describe "integration with version compatibility service" do
    it "generates script that would validate PostgreSQL 15 on Ubuntu 20.04" do
      script = generator.generate(is_replica: false)

      # Script should include validation logic
      expect(script).to include("validate_database_version")
      expect(script).to include("postgresql")
    end

    it "includes compatibility error handling" do
      script = generator.generate(is_replica: false)

      # Should have error handling for incompatible versions
      expect(script).to include("callback")
      expect(script).to include("error")
    end
  end
end
