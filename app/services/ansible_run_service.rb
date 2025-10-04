require "open3"
require_relative "database_service_factory"

class AnsibleRunService
  def initialize
  end

  def ansible_path
    Rails.root.join("lib", "ansible")
  end

  def playbook_path(node, playbook)
    database_type_slug = node.database_type_slug || "postgresql" # fallback for backward compatibility

    Rails.root.join(ansible_path, database_type_slug, playbook).to_s
  end

  def perform(node_id, playbook, vars: {})
    @node = Node.find_by_id(node_id)
    @node_id = node_id
    @playbook_name = playbook

    return unless @node

    ip = @node.get_runtime_config_value("ip_address")
    return unless ip

    ip_address = IPAddr.new(ip).to_s
    return if ip_address.nil?

    # Create log file for this Ansible run
    ansible_log_path = ansible_log_file_path(@node_id, playbook)
    ansible_log = File.open(ansible_log_path, "a")

    begin
      ansible_log.puts "=" * 80
      ansible_log.puts "[#{Time.current}] Ansible Playbook Execution"
      ansible_log.puts "Node ID: #{@node_id}"
      ansible_log.puts "Playbook: #{playbook}"
      ansible_log.puts "IP Address: #{ip_address}"
      ansible_log.puts "=" * 80
      ansible_log.flush

      hosts = [
        { name: "node-#{@node.id}", ip: ip_address, user: "root" }
      ]

      # Use a safe, hardcoded path for ansible-playbook to prevent command injection
      ansible_binary = find_ansible_binary
      return unless ansible_binary

      cmd = [ ansible_binary ]

      # Create a temporary inventory file
      inventory = Tempfile.new("ansible_inventory")
      inventory_group_name = determine_inventory_group_name(@node)
      inventory.write("[#{inventory_group_name}]\n")
      hosts.each do |host|
        content = [
          host[:ip],
          "ansible_user=#{host[:user]}"
        ]
        inventory.write("#{content.join(" ")}\n")
      end
      inventory.flush
      cmd += [ "-i", inventory.path.to_s ]

      # Create a temporary vars file
      if vars.present?
        # Validate critical variables before writing
        vars.each do |key, value|
          if key.to_s.match?(/password/i)
            if value.nil? || value.to_s.strip.empty?
              error_msg = "CRITICAL: Variable '#{key}' is nil or empty! Value: #{value.inspect}"
              Rails.logger.error error_msg
              ansible_log.puts error_msg
              ansible_log.flush
              raise ArgumentError, "Variable '#{key}' cannot be nil or empty"
            end
            Rails.logger.info "Password variable '#{key}' validated: length=#{value.to_s.length}"
            ansible_log.puts "Password variable '#{key}' validated: length=#{value.to_s.length}"
          end
        end

        varfile = Tempfile.new("ansible_vars")

        # Log variables (hide sensitive ones)
        ansible_log.puts "\nAnsible Variables:"
        vars.each do |key, value|
          if key.to_s.match?(/password|secret|key/i)
            ansible_log.puts "  #{key}: [HIDDEN - length: #{value.to_s.length}]"
          else
            ansible_log.puts "  #{key}: #{value}"
          end
        end
        ansible_log.puts ""
        ansible_log.flush

        vars.each do |key, value|
          varfile.write("#{key}: #{value}\n")
        end
        varfile.flush
        cmd += [ "-e", "@#{varfile.path}" ]
      end

      key_file = Tempfile.new("ansible_key")
      key_file.write(@node.ssh_private_key)
      key_file.chmod(0600)
      key_file.flush

      env = {}

      cmd += [
        "--private-key", key_file.path.to_s,
        "-v",  # Verbose output
        playbook_path(@node, playbook)
      ]

      ansible_log.puts "Executing command: #{cmd.join(' ')}"
      ansible_log.puts "-" * 80
      ansible_log.flush

      Rails.logger.info "Ansible log file: #{ansible_log_path}"

      buffer = ""
      # brakeman:ignore:CommandInjection - ansible binary path is validated in find_ansible_binary method
      Open3.popen2e(env, *cmd, chdir: ansible_path.to_s) do |stdin, stdout_err, wait_thr|
        stdin.close

        stdout_err.each do |line|
          line.chomp!

          # Log to file
          ansible_log.puts line
          ansible_log.flush

          # Log to Rails logger
          Rails.logger.info line

          parse_line(line)
        end

        exit_status = wait_thr.value

        ansible_log.puts "-" * 80
        ansible_log.puts "[#{Time.current}] Ansible #{exit_status.success? ? 'SUCCEEDED' : 'FAILED'} (exit code: #{exit_status.exitstatus})"
        ansible_log.puts "=" * 80
        ansible_log.flush

        Rails.logger.info "Ansible exited with status #{exit_status.exitstatus}"
        Rails.logger.info "Full Ansible log available at: #{ansible_log_path}"
      end
    ensure
      ansible_log.close if ansible_log && !ansible_log.closed?

      # Cleanup
      if defined?(inventory) && inventory
        inventory.close
        inventory.unlink
      end
      if defined?(key_file) && key_file
        key_file.close
        key_file.unlink
      end
      if defined?(varfile) && varfile
        varfile.close
        varfile.unlink
      end
    end
  end

  # Parse each line for task names or status updates
  def parse_line(line)
    # Detect a task start
    if line =~ /^TASK \[(.+)\]/
      finish_current_task
      @current_task = { name: $1.strip, status: "running", details: "" }
      broadcast(@current_task)
    elsif @current_task
      # Detect task result
      case line
      when /ok:/ then @current_task[:status] = "success"
      when /changed:/ then @current_task[:status] = "changed"
      when /failed:/ then @current_task[:status] = "failed"
      end

      # Append output
      @current_task[:details] += line + "\n"
      broadcast(@current_task)
    end
  end

  def finish_current_task
    @current_task = nil if @current_task
  end

  def broadcast(task)
    # Send JSON to ActionCable or any other system
    payload = task.to_json
    ActionCable.server.broadcast("ansible", payload)

    # In development, also broadcast to console channel for debugging
    if Rails.env.development?
      console_data = {
        timestamp: Time.current.strftime("%H:%M:%S"),
        event_type: "ansible_task",
        node_id: @node_id,
        task_name: task["name"],
        status: task["status"],
        details: task["details"],
        playbook: @playbook_name
      }
      ActionCable.server.broadcast("development_console", console_data)
    end

    # Log to Rails logger instead of console
    Rails.logger.info payload
  end

  private

  def ansible_log_file_path(node_id, playbook_name)
    log_dir = Rails.root.join("log", "ansible")
    FileUtils.mkdir_p(log_dir)
    # Sanitize playbook name for filename
    safe_playbook_name = playbook_name.gsub(/[^a-zA-Z0-9_-]/, '_')
    log_dir.join("node_#{node_id}_#{safe_playbook_name}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.log")
  end

  def find_ansible_binary
    # Define safe, known paths for ansible-playbook
    safe_paths = [
      '/usr/bin/ansible-playbook',
      '/usr/local/bin/ansible-playbook',
      '/opt/homebrew/bin/ansible-playbook',  # macOS Homebrew
      '/home/linuxbrew/.linuxbrew/bin/ansible-playbook'  # Linux Homebrew
    ]

    # Check each safe path
    safe_paths.each do |path|
      return path if File.executable?(path)
    end

    # If none of the safe paths work, try to find it in PATH but validate the result
    begin
      result = `which ansible-playbook 2>/dev/null`.chomp
      if result.present? && File.executable?(result) && result.match?(/\A[\/\w\-\.]+\z/)
        return result
      end
    rescue => e
      Rails.logger.error "Error finding ansible-playbook: #{e.message}"
    end

    Rails.logger.error "ansible-playbook not found in any safe location"
    nil
  end

  def determine_inventory_group_name(node)
    # Use database type-specific group name, with fallback for backward compatibility
    case node.database_type_slug
    when "postgresql"
      "postgres_servers"
    when "mysql"
      "mysql_servers"
    else
      "database_servers"
    end
  end
end
