require "sshkey"
require "base64"

class TerraformCreateService < TerraformBaseService
  def perform(node_id)
    @node = Node.find(node_id)
    return unless @node

    begin
      # Ensure SSH keys and root password are generated
      @node.ensure_ssh_keys!
      @node.ensure_root_password!

      # Setup working environment
      env = setup_working_directory(@node, "create")
      work_dir = env[:work_dir]
      terraform_log_path = env[:terraform_log_path]

      # Copy Terraform templates
      copy_terraform_templates(work_dir, @node.provider.provider_type)

      # Prepare variables
      vars = prepare_terraform_vars(@node)
      vars[:node_root_password] = @node.root_password

      # Generate cloud-init script for database setup
      is_replica = @node.replica?
      script_file_path = CloudInitService.new.write_script_to_file(@node.id, work_dir, is_replica)
      vars[:cloud_init_script] = script_file_path

      # Load state from DB into work dir
      load_state_from_db(work_dir, @node)

      # Write vars file
      File.write(work_dir.join("vars.tfvars"), vars_to_tfvars(vars))

      # Execute Terraform commands
      terraform_cmds = [
        "#{command} init -input=false",
        "#{command} plan -input=false -var-file=vars.tfvars -out=tfplan",
        "#{command} apply -input=false -auto-approve tfplan"
      ]

      execute_terraform_commands(terraform_cmds, work_dir, terraform_log_path)

      # Capture and process Terraform outputs
      capture_terraform_outputs(work_dir, terraform_log_path)

      # Save updated state back to DB
      save_state_to_db(work_dir, @node)

      log_completion("create", terraform_log_path)
      cleanup_on_success(work_dir)

    rescue => e
      preserve_on_failure(work_dir, "create", e)
    end
  end

  private

  def capture_terraform_outputs(work_dir, terraform_log_path)
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
  end
end
