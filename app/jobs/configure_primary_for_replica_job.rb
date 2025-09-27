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

      # Create temporary Ansible workspace
      @ansible_service.create_temp_workspace

      # Create playbook from template with variables
      playbook_file = create_primary_configuration_playbook(replication_password)

      # Execute Ansible playbook
      result = execute_ansible_playbook(playbook_file)

      if result[:success]
        Rails.logger.info "Successfully configured primary #{@primary_node.id} for replica at #{@replica_ip}"
        broadcast_job_message("Ansible playbook completed successfully", "info")

        # Update primary node status to indicate it's ready for replication
        @primary_node.broadcast_status_update("Primary configured for replica at #{@replica_ip}")

        # Broadcast to replica that primary is ready
        @replica_node.broadcast_status_update("Primary configured - ready for replication")

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

    # Define template variables
    variables = {
      'replica_ip' => @replica_ip,
      'replica_node_name' => @replica_node.name,
      'replication_password' => replication_password,
      'postgresql_version' => primary_version,
      'replica_postgresql_version' => replica_version
    }

    # Use the existing Ansible playbook template
    template_path = 'lib/ansible/postgresql/configure_primary_replication.yml'

    @ansible_service.write_playbook_from_template(
      template_path,
      'configure_primary_replication',
      variables
    )
  end

  def execute_ansible_playbook(playbook_file)
    # Get primary node IP
    primary_ip = @primary_node.get_ip_address

    if primary_ip.blank?
      return { success: false, error: "Primary node IP address not available" }
    end

    # Get SSH private key path (creates temporary file)
    ssh_key_path = create_temp_ssh_key

    # Create inventory using the service
    hosts_config = {
      'all' => [
        {
          ip: primary_ip,
          user: 'root',
          ssh_key: ssh_key_path,
          skip_host_check: true
        }
      ]
    }

    inventory_file = @ansible_service.write_inventory(hosts_config)

    # Build Ansible command
    ansible_cmd = [
      "ansible-playbook",
      "-i", inventory_file,
      playbook_file
    ]

    Rails.logger.info "Executing Ansible command: #{ansible_cmd.join(' ')}"

    # Execute Ansible playbook
    stdout, stderr, status = Open3.capture3(*ansible_cmd)

    Rails.logger.info "Ansible stdout: #{stdout}"
    Rails.logger.error "Ansible stderr: #{stderr}" if stderr.present?

    if status.success?
      { success: true, stdout: stdout }
    else
      { success: false, error: "Ansible failed: #{stderr}", stdout: stdout }
    end
  rescue => e
    { success: false, error: "Exception running Ansible: #{e.message}" }
  ensure
    # Clean up temporary SSH key file
    if ssh_key_path && File.exist?(ssh_key_path)
      File.delete(ssh_key_path)
      Rails.logger.debug "Cleaned up temporary SSH key file: #{ssh_key_path}"
    end
  end

  private

  def create_temp_ssh_key
    key_file = Tempfile.new("ansible_ssh_key")
    key_file.write(@primary_node.ssh_private_key)
    key_file.chmod(0600)
    key_file.flush
    key_file.close
    key_file.path
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
