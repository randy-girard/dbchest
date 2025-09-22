require "open3"

class AnsibleRunService
  def initialize
  end

  def ansible_path
    Rails.root.join("lib", "ansible")
  end

  def playbook_path(node, playbook)
    Rails.root.join(ansible_path, node.cluster.cluster_type, playbook).to_s
  end

  def perform(node_id, playbook, vars: {})
    @node = Node.find_by_id(node_id)
    @node_id = node_id
    @playbook_name = playbook
    
    ip = @node.get_runtime_config_value("ip_address")
    ip_address = IPAddr.new(ip).to_s

    return if ip_address.nil?

    hosts = [
      { name: "node-#{@node.id}", ip: ip_address, user: "root" }
    ]

    ansible_binary = `which ansible-playbook`.chomp
    cmd = [ ansible_binary ]

    # Create a temporary inventory file
    inventory = Tempfile.new("ansible_inventory")
    inventory.write("[postgres_servers]\n")
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
      puts "Ansible exited with status #{exit_status.exitstatus}"
    end
  ensure
    # Cleanup
    inventory.close
    inventory.unlink
    key_file.close
    key_file.unlink
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
        event_type: 'ansible_task',
        node_id: @node_id,
        task_name: task["name"],
        status: task["status"],
        details: task["details"],
        playbook: @playbook_name
      }
      ActionCable.server.broadcast("development_console", console_data)
    end
    
    # Optionally output to console
    puts payload
  end
end
