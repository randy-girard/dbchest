class ConfigurePrimaryForReplicaJob < ApplicationJob
  queue_as :default

  def perform(primary_node_id:, replica_node_id:, replica_ip:)
    @primary_node = Node.find(primary_node_id)
    @replica_node = Node.find(replica_node_id)
    @replica_ip = replica_ip

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

      # Generate Ansible playbook for primary configuration
      playbook_content = generate_primary_configuration_playbook(replication_password)

      # Write playbook to temporary file
      playbook_file = write_temp_playbook(playbook_content)

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
      # Clean up temporary playbook file
      File.delete(playbook_file) if playbook_file && File.exist?(playbook_file)
    end
  end

  private

  def generate_primary_configuration_playbook(replication_password)
    # Get database version information
    primary_version = @primary_node.database_type_version&.version || "15"
    replica_version = @replica_node.database_type_version&.version || "15"

    <<~YAML
      ---
      - name: Configure PostgreSQL primary for replication from specific replica
        hosts: all
        become: yes
        vars:
          replica_ip: "#{@replica_ip}"
          replica_name: "#{@replica_node.name}"
          replication_password: "#{replication_password}"
          postgresql_version: "#{primary_version}"
          replica_postgresql_version: "#{replica_version}"
      #{'  '}
        tasks:
          - name: Validate replica_ip is not empty
            fail:
              msg: "replica_ip variable is empty or undefined. Cannot configure pg_hba.conf"
            when: replica_ip is undefined or replica_ip == "" or replica_ip is none

          - name: Validate replica_ip format
            fail:
              msg: "replica_ip '{{ replica_ip }}' is not a valid IP address format"
            when: replica_ip is not match("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$")
          - name: Check if replication user exists
            become_user: postgres
            postgresql_query:
              db: postgres
              query: "SELECT 1 FROM pg_user WHERE usename = 'replication'"
            register: replication_user_exists
            ignore_errors: yes

          - name: Create replication user if not exists
            become_user: postgres
            postgresql_user:
              name: replication
              password: "{{ replication_password }}"
              role_attr_flags: REPLICATION,LOGIN
              conn_limit: 10
              state: present
            when: replication_user_exists.query_result | length == 0

          - name: Check if pg_hba.conf entry exists for this replica IP
            lineinfile:
              path: /etc/postgresql/*/main/pg_hba.conf
              regexp: "^host\\s+replication\\s+replication\\s+{{ replica_ip }}/32"
              state: absent
            check_mode: yes
            register: pg_hba_check

          - name: Add pg_hba.conf entry for replica
            lineinfile:
              path: /etc/postgresql/*/main/pg_hba.conf
              line: "# Replication from {{ replica_name }} ({{ replica_ip }})"
              insertafter: "^# Database administrative login by Unix domain socket"
              state: present
            when: pg_hba_check.changed

          - name: Add replication host entry for replica
            lineinfile:
              path: /etc/postgresql/*/main/pg_hba.conf
              line: "host    replication     replication     {{ replica_ip }}/32          md5"
              insertafter: "# Replication from {{ replica_name }}"
              state: present
            when: pg_hba_check.changed

          - name: Reload PostgreSQL configuration
            systemd:
              name: postgresql
              state: reloaded
            when: pg_hba_check.changed

          - name: Verify PostgreSQL is running
            systemd:
              name: postgresql
              state: started
              enabled: yes

          - name: Test replication user connection
            become_user: postgres
            postgresql_query:
              db: postgres
              login_user: replication
              login_password: "{{ replication_password }}"
              query: "SELECT 1"
            register: replication_test
      #{'      '}
          - name: Configuration verification
            debug:
              msg: "Primary successfully configured for replication from {{ replica_ip }}"
            when: replication_test is succeeded
    YAML
  end

  def write_temp_playbook(content)
    temp_file = Tempfile.new([ "configure_primary_", ".yml" ])
    temp_file.write(content)
    temp_file.close
    temp_file.path
  end

  def execute_ansible_playbook(playbook_file)
    # Get primary node IP
    primary_ip = @primary_node.get_ip_address

    if primary_ip.blank?
      return { success: false, error: "Primary node IP address not available" }
    end

    # Build Ansible command
    ansible_cmd = [
      "ansible-playbook",
      "-i", "#{primary_ip},",
      "--private-key", @primary_node.ssh_private_key_path,
      "--user", "root",
      "--ssh-common-args", "-o StrictHostKeyChecking=no",
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
  end

  private

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
