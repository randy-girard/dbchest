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

    hosts = [
      { name: "node-#{@node.id}", ip: ip_address, user: "root" }
    ]

    ansible_binary = `which ansible-playbook`.chomp
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
      varfile = Tempfile.new("ansible_vars")
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
      playbook_path(@node, playbook)
    ]

    buffer = ""
    Open3.popen2e(env, *cmd, chdir: ansible_path.to_s) do |stdin, stdout_err, wait_thr|
      stdin.close

      stdout_err.each do |line|
        line.chomp!
        Rails.logger.info line # always print to console

        parse_line(line)
      end

      exit_status = wait_thr.value
      Rails.logger.info "Ansible exited with status #{exit_status.exitstatus}"
    end
  ensure
    # Cleanup
    if defined?(inventory) && inventory
      inventory.close
      inventory.unlink
    end
    if defined?(key_file) && key_file
      key_file.close
      key_file.unlink
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
