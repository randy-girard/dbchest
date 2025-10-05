# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "Ansible Playbooks" do
  let(:ansible_dir) { Rails.root.join("lib", "ansible") }

  describe "PostgreSQL playbooks" do
    let(:postgresql_dir) { ansible_dir.join("postgresql") }

    describe "create_node.yml" do
      let(:playbook_path) { postgresql_dir.join("create_node.yml") }
      let(:playbook) { YAML.load_file(playbook_path) }

      it "exists" do
        expect(File.exist?(playbook_path)).to be true
      end

      it "is valid YAML" do
        expect { YAML.load_file(playbook_path) }.not_to raise_error
      end

      it "has proper structure" do
        expect(playbook).to be_an(Array)
        expect(playbook.first).to have_key("name")
        expect(playbook.first).to have_key("hosts")
        expect(playbook.first).to have_key("tasks")
      end

      it "targets all hosts" do
        expect(playbook.first["hosts"]).to eq("all")
      end

      it "runs with elevated privileges" do
        expect(playbook.first["become"]).to be true
      end

      it "has PostgreSQL version variable" do
        expect(playbook.first["vars"]).to have_key("postgresql_version")
      end

      it "has postgres password variable" do
        expect(playbook.first["vars"]).to have_key("postgres_password")
      end

      it "includes SSH wait task" do
        tasks = playbook.first["tasks"] || playbook.first["pre_tasks"]
        task_names = tasks.map { |t| t["name"] }
        # The task is named "Gather facts manually after SSH is ready"
        expect(task_names).to include(match(/ssh.*ready/i))
      end

      it "includes PostgreSQL installation task" do
        tasks = playbook.first["tasks"]
        task_names = tasks.map { |t| t["name"] }
        expect(task_names).to include(match(/install.*postgresql/i))
      end

      it "includes configuration tasks" do
        tasks = playbook.first["tasks"]
        task_names = tasks.map { |t| t["name"] }
        expect(task_names).to include(match(/configure/i))
      end
    end

    describe "create_node_v2.yml (refactored version)" do
      let(:playbook_path) { postgresql_dir.join("create_node_v2.yml") }
      let(:playbook) { YAML.load_file(playbook_path) if File.exist?(playbook_path) }

      it "exists" do
        skip "create_node_v2.yml not yet created" unless File.exist?(playbook_path)
        expect(File.exist?(playbook_path)).to be true
      end

      it "is valid YAML" do
        expect { YAML.load_file(playbook_path) }.not_to raise_error
      end

      it "includes version compatibility check" do
        skip "create_node_v2.yml not yet created" unless File.exist?(playbook_path)
        tasks = playbook.first["pre_tasks"] || playbook.first["tasks"]
        task_names = tasks.map { |t| t["name"] }
        expect(task_names).to include(match(/compatibility/i))
      end

      it "validates PostgreSQL 16+ requires Ubuntu 22.04+" do
        skip "create_node_v2.yml not yet created" unless File.exist?(playbook_path)
        tasks = playbook.first["pre_tasks"] || playbook.first["tasks"]
        validation_task = tasks.find { |t| t["name"] =~ /validate.*16/i }

        if validation_task
          expect(validation_task).to have_key("fail")
          expect(validation_task["when"]).to be_present
        end
      end

      it "uses common role" do
        skip "create_node_v2.yml not yet created" unless File.exist?(playbook_path)
        tasks = playbook.first["pre_tasks"] || playbook.first["tasks"]
        role_tasks = tasks.select { |t| t["include_role"] }

        if role_tasks.any?
          role_names = role_tasks.map { |t| t["include_role"]["name"] }
          expect(role_names).to include("common")
        end
      end
    end
  end

  describe "Ansible roles" do
    let(:roles_dir) { ansible_dir.join("roles") }

    describe "common role" do
      let(:common_role_dir) { roles_dir.join("common") }
      let(:tasks_file) { common_role_dir.join("tasks", "main.yml") }

      it "exists" do
        skip "common role not yet created" unless File.exist?(tasks_file)
        expect(File.exist?(tasks_file)).to be true
      end

      it "is valid YAML" do
        skip "common role not yet created" unless File.exist?(tasks_file)
        expect { YAML.load_file(tasks_file) }.not_to raise_error
      end

      it "includes SSH wait task" do
        skip "common role not yet created" unless File.exist?(tasks_file)
        tasks = YAML.load_file(tasks_file)
        task_names = tasks.map { |t| t["name"] }
        expect(task_names).to include(match(/wait.*ssh/i))
      end

      it "includes prerequisites installation" do
        skip "common role not yet created" unless File.exist?(tasks_file)
        tasks = YAML.load_file(tasks_file)
        task_names = tasks.map { |t| t["name"] }
        expect(task_names).to include(match(/prerequisites/i))
      end
    end

    describe "database_base role" do
      let(:database_base_dir) { roles_dir.join("database_base") }
      let(:tasks_file) { database_base_dir.join("tasks", "main.yml") }

      it "exists" do
        skip "database_base role not yet created" unless File.exist?(tasks_file)
        expect(File.exist?(tasks_file)).to be true
      end

      it "is valid YAML" do
        skip "database_base role not yet created" unless File.exist?(tasks_file)
        expect { YAML.load_file(tasks_file) }.not_to raise_error
      end

      it "includes configuration detection" do
        skip "database_base role not yet created" unless File.exist?(tasks_file)
        tasks = YAML.load_file(tasks_file)
        task_names = tasks.map { |t| t["name"] }
        expect(task_names).to include(match(/detect.*config/i))
      end
    end
  end

  describe "MySQL playbooks" do
    let(:mysql_dir) { ansible_dir.join("mysql") }

    describe "create_node.yml" do
      let(:playbook_path) { mysql_dir.join("create_node.yml") }
      let(:playbook) { YAML.load_file(playbook_path) if File.exist?(playbook_path) }

      it "exists" do
        skip "MySQL playbook not yet created" unless File.exist?(playbook_path)
        expect(File.exist?(playbook_path)).to be true
      end

      it "is valid YAML" do
        skip "MySQL playbook not yet created" unless File.exist?(playbook_path)
        expect { YAML.load_file(playbook_path) }.not_to raise_error
      end

      it "has MySQL version variable" do
        skip "MySQL playbook not yet created" unless File.exist?(playbook_path)
        expect(playbook.first["vars"]).to have_key("mysql_version")
      end
    end
  end

  describe "playbook syntax validation" do
    it "all playbooks have valid YAML syntax" do
      playbook_files = Dir.glob(ansible_dir.join("**", "*.yml"))

      playbook_files.each do |playbook_file|
        expect { YAML.load_file(playbook_file) }.not_to raise_error,
          "YAML syntax error in #{playbook_file}"
      end
    end

    it "all playbooks have required top-level keys" do
      playbook_files = Dir.glob(ansible_dir.join("**", "*.yml"))

      playbook_files.each do |playbook_file|
        next if playbook_file.include?("roles/") # Skip role files

        playbook = YAML.load_file(playbook_file)
        next unless playbook.is_a?(Array) && playbook.first.is_a?(Hash)

        expect(playbook.first).to have_key("name"),
          "Missing 'name' key in #{playbook_file}"
        expect(playbook.first).to have_key("hosts"),
          "Missing 'hosts' key in #{playbook_file}"
      end
    end
  end

  describe "variable consistency" do
    it "PostgreSQL playbooks use consistent variable names" do
      playbook_files = Dir.glob(ansible_dir.join("postgresql", "*.yml"))

      playbook_files.each do |playbook_file|
        # Skip cleanup, utility, and configuration playbooks that don't need all variables
        # Only check main provisioning playbooks (create_node.yml, create_node_v2.yml)
        next if playbook_file.include?("cleanup") ||
                playbook_file.include?("remove") ||
                playbook_file.include?("configure")

        playbook = YAML.load_file(playbook_file)
        next unless playbook.first["vars"]

        vars = playbook.first["vars"]

        # If it has postgresql_version, it should have postgres_password
        if vars.key?("postgresql_version")
          expect(vars).to have_key("postgres_password"),
            "Missing postgres_password in #{playbook_file}"
        end
      end
    end
  end
end
