class ConfigurePrimaryForReplicaJob < ApplicationJob
  queue_as :default

  def perform(primary_node_id:, replica_node_id:, replica_ip:)
    @primary_node = Node.find(primary_node_id)
    @replica_node = Node.find(replica_node_id)
    @replica_ip = replica_ip
    @ansible_service = AnsiblePlaybookService.new

    # Broadcast job start to development console
    broadcast_job_message("Starting primary configuration job for replica at #{@replica_ip}", "info")

    # Validate replica_ip is present and valid
    if @replica_ip.blank?
      error_msg = "replica_ip is blank or empty"
      Rails.logger.error "ConfigurePrimaryForReplicaJob failed: #{error_msg}"
      broadcast_job_message("Job failed: #{error_msg}", "error")
      @replica_node.update_status!("error", "Primary configuration failed: #{error_msg}")
      return
    end

    # Basic IP address validation
    unless @replica_ip.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
      error_msg = "replica_ip '#{@replica_ip}' is not a valid IP address"
      Rails.logger.error "ConfigurePrimaryForReplicaJob failed: #{error_msg}"
      broadcast_job_message("Job failed: #{error_msg}", "error")
      @replica_node.update_status!("error", "Primary configuration failed: #{error_msg}")
      return
    end

    Rails.logger.info "Starting Ansible job to configure primary #{@primary_node.id} for replica #{@replica_node.id} at IP #{@replica_ip}"
    broadcast_job_message("Validated replica IP #{@replica_ip}, proceeding with Ansible configuration", "info")

    begin
      # Ensure primary node has replication password
      replication_password = @primary_node.ensure_replication_password!

      # Validate replication password is not blank
      if replication_password.blank?
        error_msg = "replication_password is blank or empty after ensure_replication_password!"
        Rails.logger.error "ConfigurePrimaryForReplicaJob failed: #{error_msg}"
        broadcast_job_message("Job failed: #{error_msg}", "error")
        @replica_node.update_status!("error", "Primary configuration failed: #{error_msg}")
        return
      end

      Rails.logger.info "Replication password retrieved: #{replication_password[0..5]}... (length: #{replication_password.length})"
      broadcast_job_message("Replication password validated (length: #{replication_password.length})", "info")

      # Create temporary Ansible workspace
      @ansible_service.create_temp_workspace

      # Create playbook from template with variables
      playbook_file = create_primary_configuration_playbook(replication_password)

      # Execute Ansible playbook
      result = execute_ansible_playbook(playbook_file)

      if result[:success]
        Rails.logger.info "Successfully configured primary #{@primary_node.id} for replica at #{@replica_ip}"
        broadcast_job_message("Ansible playbook completed successfully", "info")

        # Log success messages
        Rails.logger.info "Primary node #{@primary_node.id} configured for replica at #{@replica_ip}"
        Rails.logger.info "Replica node #{@replica_node.id} can now proceed with replication setup"

        broadcast_job_message("Job completed successfully - primary ready for replication", "info")
      else
        Rails.logger.error "Failed to configure primary #{@primary_node.id}: #{result[:error]}"
        broadcast_job_message("Ansible playbook failed: #{result[:error]}", "error")
        @replica_node.update_status!("error", "Failed to configure primary: #{result[:error]}")
      end

    rescue => e
      Rails.logger.error "Error in ConfigurePrimaryForReplicaJob: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @replica_node.update_status!("error", "Primary configuration job failed: #{e.message}")
    ensure
      # Clean up temporary Ansible workspace
      @ansible_service&.cleanup!
    end
  end

  private

  def create_primary_configuration_playbook(replication_password)
    # Get database version information
    primary_version = @primary_node.database_type_version&.version || "15"
    replica_version = @replica_node.database_type_version&.version || "15"

    # Store variables for later use in execute_ansible_playbook
    @playbook_variables = {
      "replica_ip" => @replica_ip,
      "replica_node_name" => @replica_node.name,
      "replication_password" => replication_password,
      "postgresql_version" => primary_version,
      "replica_postgresql_version" => replica_version
    }

    # Copy the playbook to temp workspace without variable replacement
    # Variables will be passed via Ansible extra vars instead
    template_path = "lib/ansible/postgresql/configure_primary_replication.yml"
    template_content = File.read(Rails.root.join(template_path))

    @ansible_service.ensure_temp_workspace_exists
    playbook_path = File.join(@ansible_service.workspace_path, "configure_primary_replication.yml")
    File.write(playbook_path, template_content)

    Rails.logger.info "Created playbook: #{playbook_path}"
    playbook_path
  end

  def execute_ansible_playbook(playbook_file)
    # Get primary node IP
    primary_ip = @primary_node.get_ip_address

    if primary_ip.blank?
      return { success: false, error: "Primary node IP address not available" }
    end

    # Create log file for this Ansible run
    ansible_log_path = ansible_log_file_path(@replica_node.id)
    ansible_log = File.open(ansible_log_path, "a")
    ssh_key_file = nil

    begin
      ansible_log.puts "=" * 80
      ansible_log.puts "[#{Time.current}] ConfigurePrimaryForReplicaJob - Ansible Execution"
      ansible_log.puts "Primary Node ID: #{@primary_node.id}"
      ansible_log.puts "Replica Node ID: #{@replica_node.id}"
      ansible_log.puts "Replica IP: #{@replica_ip}"
      ansible_log.puts "=" * 80
      ansible_log.flush

      # Create SSH private key file (keep file handle to prevent deletion)
      ssh_key_file = Tempfile.new(["ansible_ssh_key", ".pem"])
      ssh_key_file.write(@primary_node.ssh_private_key)
      ssh_key_file.chmod(0600)
      ssh_key_file.flush
      ssh_key_path = ssh_key_file.path

      ansible_log.puts "Created SSH key file: #{ssh_key_path}"
      ansible_log.flush

      # Create inventory using the service
      hosts_config = {
        "all" => [
          {
            ip: primary_ip,
            user: "root",
            ssh_key: ssh_key_path,
            skip_host_check: true
          }
        ]
      }

      inventory_file = @ansible_service.write_inventory(hosts_config)

      # Create vars file with playbook variables
      vars_file = @ansible_service.write_vars_file(@playbook_variables)

      # Log variables (excluding password)
      ansible_log.puts "\nAnsible Variables:"
      @playbook_variables.except('replication_password').each do |key, value|
        ansible_log.puts "  #{key}: #{value}"
      end
      ansible_log.puts "  replication_password: [HIDDEN - length: #{@playbook_variables['replication_password']&.length || 0}]"
      ansible_log.puts ""
      ansible_log.flush

      # Build Ansible command with extra vars
      # Set ANSIBLE_HOST_KEY_CHECKING=False to avoid known_hosts issues
      env = { "ANSIBLE_HOST_KEY_CHECKING" => "False" }

      ansible_cmd = [
        "ansible-playbook",
        "-i", inventory_file,
        "-e", "@#{vars_file}",
        "-v",  # Verbose output
        playbook_file
      ]

      ansible_log.puts "Executing command: #{ansible_cmd.join(' ')}"
      ansible_log.puts "-" * 80
      ansible_log.flush

      Rails.logger.info "Executing Ansible command: #{ansible_cmd.join(' ')}"
      Rails.logger.info "Ansible log file: #{ansible_log_path}"
      Rails.logger.info "Ansible variables: #{@playbook_variables.except('replication_password').inspect} (password hidden)"

      # Execute Ansible playbook with streaming output
      Open3.popen2e(env, *ansible_cmd) do |stdin, stdout_err, wait_thr|
        stdin.close

        stdout_err.each do |line|
          line.chomp!

          # Log to file
          ansible_log.puts line
          ansible_log.flush

          # Log to Rails logger
          Rails.logger.info "[Ansible] #{line}"
        end

        status = wait_thr.value

        ansible_log.puts "-" * 80
        ansible_log.puts "[#{Time.current}] Ansible #{status.success? ? 'SUCCEEDED' : 'FAILED'} (exit code: #{status.exitstatus})"
        ansible_log.puts "=" * 80
        ansible_log.flush

        if status.success?
          Rails.logger.info "Ansible playbook completed successfully"
          return { success: true, log_path: ansible_log_path }
        else
          Rails.logger.error "Ansible playbook failed with exit code: #{status.exitstatus}"
          return { success: false, error: "Ansible failed with exit code #{status.exitstatus}. See log: #{ansible_log_path}", log_path: ansible_log_path }
        end
      end
    rescue => e
      ansible_log.puts "\nEXCEPTION: #{e.message}"
      ansible_log.puts e.backtrace.join("\n")
      ansible_log.flush
      { success: false, error: "Exception running Ansible: #{e.message}", log_path: ansible_log_path }
    ensure
      ansible_log.close if ansible_log && !ansible_log.closed?

      # Clean up temporary SSH key file
      if ssh_key_file
        ssh_key_file.close
        ssh_key_file.unlink
        Rails.logger.debug "Cleaned up temporary SSH key file"
      end
    end
  end

  private

  def ansible_log_file_path(node_id)
    log_dir = Rails.root.join("log", "ansible")
    FileUtils.mkdir_p(log_dir)
    log_dir.join("configure_primary_replica_node_#{node_id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.log")
  end

  def broadcast_job_message(message, level = "info")
    return unless Rails.env.development?

    console_data = {
      timestamp: Time.current.strftime("%H:%M:%S"),
      event_type: "job_message",
      job_name: "ConfigurePrimaryForReplicaJob",
      primary_node_id: @primary_node&.id,
      replica_node_id: @replica_node&.id,
      replica_ip: @replica_ip,
      message: message,
      level: level
    }
    ActionCable.server.broadcast("development_console", console_data)
  end
end
