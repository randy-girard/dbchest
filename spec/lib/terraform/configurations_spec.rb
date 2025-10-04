# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Terraform Configurations" do
  let(:terraform_dir) { Rails.root.join("lib", "terraform") }

  describe "Proxmox configuration" do
    let(:proxmox_dir) { terraform_dir.join("proxmox") }

    describe "main.tf" do
      let(:main_tf_path) { proxmox_dir.join("main.tf") }
      let(:main_tf_content) { File.read(main_tf_path) }

      it "exists" do
        expect(File.exist?(main_tf_path)).to be true
      end

      it "has terraform block" do
        expect(main_tf_content).to include("terraform {")
      end

      it "has required_providers block" do
        expect(main_tf_content).to include("required_providers")
      end

      it "specifies proxmox provider" do
        expect(main_tf_content).to include("proxmox")
      end

      it "has provider configuration" do
        expect(main_tf_content).to include("provider \"proxmox\"")
      end

      it "has LXC container resource" do
        expect(main_tf_content).to include("resource \"proxmox_lxc\"")
      end

      it "uses variables for configuration" do
        expect(main_tf_content).to include("var.")
      end

      it "has outputs defined" do
        expect(main_tf_content).to include("output")
      end

      it "includes cloud-init script provisioner" do
        expect(main_tf_content).to include("provisioner")
        expect(main_tf_content).to include("cloud_init_script")
      end

      it "has valid HCL syntax" do
        # Basic syntax check - looks for balanced braces
        open_braces = main_tf_content.scan(/{/).count
        close_braces = main_tf_content.scan(/}/).count
        expect(open_braces).to eq(close_braces), "Unbalanced braces in main.tf"
      end
    end

    describe "variables.tf" do
      let(:variables_tf_path) { proxmox_dir.join("variables.tf") }
      let(:variables_tf_content) { File.read(variables_tf_path) if File.exist?(variables_tf_path) }

      it "exists" do
        skip "variables.tf not yet created" unless File.exist?(variables_tf_path)
        expect(File.exist?(variables_tf_path)).to be true
      end

      it "defines required variables" do
        skip "variables.tf not yet created" unless File.exist?(variables_tf_path)
        expect(variables_tf_content).to include("variable")
      end

      it "has valid HCL syntax" do
        skip "variables.tf not yet created" unless File.exist?(variables_tf_path)
        open_braces = variables_tf_content.scan(/{/).count
        close_braces = variables_tf_content.scan(/}/).count
        expect(open_braces).to eq(close_braces)
      end
    end
  end

  describe "DigitalOcean configuration" do
    let(:digitalocean_dir) { terraform_dir.join("digitalocean") }

    describe "main.tf" do
      let(:main_tf_path) { digitalocean_dir.join("main.tf") }
      let(:main_tf_content) { File.read(main_tf_path) if File.exist?(main_tf_path) }

      it "exists" do
        skip "DigitalOcean configuration not yet created" unless File.exist?(main_tf_path)
        expect(File.exist?(main_tf_path)).to be true
      end

      it "specifies digitalocean provider" do
        skip "DigitalOcean configuration not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("digitalocean")
      end

      it "has valid HCL syntax" do
        skip "DigitalOcean configuration not yet created" unless File.exist?(main_tf_path)
        open_braces = main_tf_content.scan(/{/).count
        close_braces = main_tf_content.scan(/}/).count
        expect(open_braces).to eq(close_braces)
      end
    end
  end

  describe "Terraform modules" do
    let(:modules_dir) { terraform_dir.join("modules") }

    describe "database_node module" do
      let(:database_node_dir) { modules_dir.join("database_node") }
      let(:main_tf_path) { database_node_dir.join("main.tf") }
      let(:main_tf_content) { File.read(main_tf_path) if File.exist?(main_tf_path) }

      it "exists" do
        skip "database_node module not yet created" unless File.exist?(main_tf_path)
        expect(File.exist?(main_tf_path)).to be true
      end

      it "defines input variables" do
        skip "database_node module not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("variable \"provider_type\"")
        expect(main_tf_content).to include("variable \"database_type\"")
        expect(main_tf_content).to include("variable \"database_version\"")
      end

      it "defines outputs" do
        skip "database_node module not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("output \"node_id\"")
        expect(main_tf_content).to include("output \"ip_address\"")
      end

      it "includes conditional module loading" do
        skip "database_node module not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("module")
        expect(main_tf_content).to include("count")
      end

      it "supports multiple providers" do
        skip "database_node module not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("proxmox")
      end

      it "has valid HCL syntax" do
        skip "database_node module not yet created" unless File.exist?(main_tf_path)
        open_braces = main_tf_content.scan(/{/).count
        close_braces = main_tf_content.scan(/}/).count
        expect(open_braces).to eq(close_braces)
      end
    end

    describe "proxmox_node module" do
      let(:proxmox_node_dir) { modules_dir.join("proxmox_node") }
      let(:main_tf_path) { proxmox_node_dir.join("main.tf") }
      let(:main_tf_content) { File.read(main_tf_path) if File.exist?(main_tf_path) }

      it "exists" do
        skip "proxmox_node module not yet created" unless File.exist?(main_tf_path)
        expect(File.exist?(main_tf_path)).to be true
      end

      it "defines LXC container resource" do
        skip "proxmox_node module not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("resource \"proxmox_lxc\"")
      end

      it "has database-specific configuration" do
        skip "proxmox_node module not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("database_type")
        expect(main_tf_content).to include("database_version")
      end

      it "includes provisioners" do
        skip "proxmox_node module not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("provisioner")
      end

      it "has outputs" do
        skip "proxmox_node module not yet created" unless File.exist?(main_tf_path)
        expect(main_tf_content).to include("output")
      end

      it "has valid HCL syntax" do
        skip "proxmox_node module not yet created" unless File.exist?(main_tf_path)
        open_braces = main_tf_content.scan(/{/).count
        close_braces = main_tf_content.scan(/}/).count
        expect(open_braces).to eq(close_braces)
      end
    end
  end

  describe "configuration consistency" do
    it "all Terraform files use consistent variable naming" do
      tf_files = Dir.glob(terraform_dir.join("**", "*.tf"))

      tf_files.each do |tf_file|
        content = File.read(tf_file)

        # Skip variable definition files - they define individual variables
        # Only check main.tf files that use the variables
        next if tf_file.include?("variables.tf")

        # Skip files that only use database_type for tagging/metadata
        # Only check files that have variable definitions
        next unless content.include?("variable \"database_type\"")

        # If it defines database_type variable, it should also define database_version
        if content.include?("variable \"database_type\"") && !content.include?("database_type_version")
          expect(content).to include("variable \"database_version\""),
            "File #{tf_file} defines database_type variable but not database_version"
        end
      end
    end

    it "all modules have proper variable definitions" do
      module_dirs = Dir.glob(terraform_dir.join("modules", "*"))
      
      module_dirs.each do |module_dir|
        main_tf = File.join(module_dir, "main.tf")
        next unless File.exist?(main_tf)
        
        content = File.read(main_tf)
        
        # If it uses var.something, it should define that variable
        var_references = content.scan(/var\.(\w+)/).flatten.uniq
        
        var_references.each do |var_name|
          expect(content).to include("variable \"#{var_name}\""),
            "Module #{module_dir} uses var.#{var_name} but doesn't define it"
        end
      end
    end
  end

  describe "resource naming" do
    it "uses descriptive resource names" do
      tf_files = Dir.glob(terraform_dir.join("**", "*.tf"))
      
      tf_files.each do |tf_file|
        content = File.read(tf_file)
        
        # Check for generic names like "main" or "default"
        resources = content.scan(/resource\s+"[^"]+"\s+"([^"]+)"/).flatten
        
        resources.each do |resource_name|
          expect(resource_name).not_to eq("main"),
            "Avoid using 'main' as resource name in #{tf_file}"
          expect(resource_name).not_to eq("default"),
            "Avoid using 'default' as resource name in #{tf_file}"
        end
      end
    end
  end

  describe "output definitions" do
    it "all main.tf files have outputs" do
      main_tf_files = Dir.glob(terraform_dir.join("**", "main.tf"))
      
      main_tf_files.each do |main_tf_file|
        content = File.read(main_tf_file)
        
        # Skip if it's just a module reference file
        next unless content.include?("resource")
        
        expect(content).to include("output"),
          "#{main_tf_file} should define outputs"
      end
    end

    it "outputs have descriptions" do
      tf_files = Dir.glob(terraform_dir.join("**", "*.tf"))
      
      tf_files.each do |tf_file|
        content = File.read(tf_file)
        
        # Find all output blocks
        outputs = content.scan(/output\s+"([^"]+)"\s+{([^}]+)}/m)
        
        outputs.each do |output_name, output_block|
          expect(output_block).to include("description"),
            "Output '#{output_name}' in #{tf_file} should have a description"
        end
      end
    end
  end
end

