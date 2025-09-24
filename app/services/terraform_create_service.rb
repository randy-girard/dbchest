require "sshkey"
require "base64"

class TerraformCreateService
  include TerraformCommon

  def initialize
  end

  def perform(node_id)
    @node = Node.find(node_id)

    if @node
      begin
        # Ensure SSH keys and root password are generated
        @node.ensure_ssh_keys!
        @node.ensure_root_password!

        provider_type = @node.provider.provider_type

        # Create isolated working directory for this run
        run_id = SecureRandom.hex(8)
        work_dir = Rails.root.join("tmp", "terraform_runs", run_id)
        FileUtils.mkdir_p(work_dir)

        # Set up dedicated Terraform log file
        terraform_log_path = terraform_log_file_path(@node.id, run_id)
        Rails.logger.info "Terraform logs will be written to: #{terraform_log_path}"

        # Copy Terraform templates into working dir
        provider_key = provider_type.key
        unless ALLOWED_PROVIDER_KEYS.include?(provider_key)
          raise ArgumentError, "Invalid provider type"
        end

        source_dir = Rails.root.join("lib", "terraform", provider_key)
        FileUtils.cp_r("#{source_dir}/.", work_dir)

        vars = {}

        # Provider configuration - expand into individual variables
        provider_config = @node.provider.terraform_vars.dup

        # Add each provider config item as individual variables
        provider_config.each do |key, value|
          vars[key.to_sym] = value
        end

        # Node-specific credentials
        vars[:ssh_public_key] = @node.ssh_public_key
        vars[:ssh_private_key] = @node.ssh_private_key
        vars[:node_root_password] = @node.root_password
        vars[:name] = @node.name
                           .to_s
                           .downcase
                           .gsub(/[^a-z0-9]+/, "-")
                           .gsub(/^-+|-+$/, "")

        # Add database type and version information
        vars[:database_type] = @node.database_type_slug
        vars[:database_version] = @node.database_version
        vars[:node_id] = @node.id.to_s
        vars[:is_replica] = @node.replica?
        vars[:primary_node_ip] = @node.parent_node&.get_ip_address || ""

        # Add network configuration from node settings
        network_config = {}
        subnet_id = nil
        bridge = "vmbr0" # default

        @node.node_settings.each do |node_setting|
          vars[node_setting.key] = node_setting.value

          # Extract network-related settings for network_config
          case node_setting.key
          when "network", "subnet"
            subnet_id = node_setting.value
          when "bridge"
            bridge = node_setting.value
          end
        end

        # Set network_config if we have subnet information
        if subnet_id.present?
          vars[:network_config] = {
            subnet_id: subnet_id,
            bridge: bridge
          }
        end

        # Generate cloud-init script for database setup
        is_replica = @node.replica?
        script_file_path = CloudInitService.new.write_script_to_file(@node.id, work_dir, is_replica)
        vars[:cloud_init_script] = script_file_path

        # Load state from DB into work dir
        load_state_from_db(work_dir, @node)

        # Write vars file
        File.write(work_dir.join("vars.tfvars"), vars_to_tfvars(vars))

        # Run Terraform commands
        terraform_cmds = [
          "#{command} init -input=false",
          "#{command} plan -input=false -var-file=vars.tfvars -out=tfplan",
          "#{command} apply -input=false -auto-approve tfplan"
        ]

        terraform_cmds.each do |cmd|
          run_cmd(cmd, work_dir, terraform_log_path)
        end

        # Capture Terraform outputs
        json, status = Open3.capture2(command, "output", "-json", chdir: work_dir)

        # Log the output command to our log file
        File.open(terraform_log_path, "a") do |log|
          log.puts "=" * 80
          log.puts "[#{Time.current}] Capturing Terraform outputs"
          log.puts "=" * 80
          log.puts json
          log.puts "=" * 80
        end

        data = JSON.parse(json)
        @node.runtime_config = data
        @node.save

        # Save updated state back to DB
        save_state_to_db(work_dir, @node)

        Rails.logger.info "Terraform deployment completed. Full logs available at: #{terraform_log_path}"

        # Clean up working directory only on success
        FileUtils.rm_rf(work_dir) if work_dir && Dir.exist?(work_dir)

      rescue => e
        # On failure, preserve working directory for debugging
        Rails.logger.error "Terraform deployment failed. Working directory preserved at: #{work_dir}"
        Rails.logger.error "Error: #{e.message}"
        raise e
      end
    end
  end
end
