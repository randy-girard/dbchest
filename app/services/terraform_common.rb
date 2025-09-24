module TerraformCommon
  ALLOWED_PROVIDER_KEYS = %w[aws linode proxmox gcp azure].freeze

  private

  def command
    `which terraform`.chomp
  end

  def vars_to_tfvars(vars)
    vars.map do |k, v|
      case k.to_s
      when "cloud_init_user_data"
        # Don't escape base64-encoded cloud_init_user_data, it only contains safe characters
        if v.to_s.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)
          "#{k} = \"#{v}\""
        else
          # Not base64, escape normally
          escaped_v = v.to_s.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", '\\n').gsub("\r", '\\r')
          "#{k} = \"#{escaped_v}\""
        end
      when "cloud_init_script"
        # Pass the script file path instead of the content
        "#{k} = \"#{v}\""
      when "ssh_private_key"
        # Use heredoc syntax for SSH private keys to preserve formatting
        "#{k} = <<-EOT\n#{v}\nEOT"
      when "ssh_public_key"
        # Use heredoc syntax for SSH public keys to avoid long line issues
        "#{k} = <<-EOT\n#{v}\nEOT"

      else
        # Escape quotes, backslashes, and newlines for all other strings
        escaped_v = v.to_s.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", '\\n').gsub("\r", '\\r')
        "#{k} = \"#{escaped_v}\""
      end
    end.join("\n")
  end

  def run_cmd(cmd, dir, log_file_path = nil)
    # Create a dedicated terraform log file if specified
    terraform_log = nil
    if log_file_path
      terraform_log = File.open(log_file_path, "a")
      terraform_log.puts "=" * 80
      terraform_log.puts "[#{Time.current}] Running: #{cmd}"
      terraform_log.puts "=" * 80
      terraform_log.flush
    end

    Open3.popen2e(cmd, chdir: dir) do |stdin, stdout_err, wait_thr|
      stdout_err.each do |line|
        line.chomp!

        # Log to Rails logger (existing behavior)
        Rails.logger.info line

        # Log to dedicated Terraform file
        if terraform_log
          terraform_log.puts line
          terraform_log.flush
        end

        # Broadcast to ActionCable (existing behavior)
        broadcast_log(line)
      end

      status = wait_thr.value

      if terraform_log
        terraform_log.puts "-" * 80
        terraform_log.puts "[#{Time.current}] Command #{status.success? ? 'SUCCEEDED' : 'FAILED'} (exit code: #{status.exitstatus})"
        terraform_log.puts "-" * 80
        terraform_log.close
      end

      raise "Terraform command failed: #{cmd}" unless status.success?
    end
  end

  def terraform_log_file_path(node_id, run_id)
    log_dir = Rails.root.join("log", "terraform")
    FileUtils.mkdir_p(log_dir)
    log_dir.join("node_#{node_id}_#{run_id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.log")
  end

  def broadcast_log(line)
    ActionCable.server.broadcast("terraform_logs_channel", { message: line })

    # In development, also broadcast to console channel for debugging
    if Rails.env.development?
      console_data = {
        timestamp: Time.current.strftime("%H:%M:%S"),
        event_type: "terraform_log",
        message: line
      }
      ActionCable.server.broadcast("development_console", console_data)
    end
  end

  def load_state_from_db(work_dir, record)
    if record&.terraform_state.present?
      File.write(File.join(work_dir, "terraform.tfstate"), record.terraform_state)
    end
  end

  def save_state_to_db(work_dir, record)
    state_json = File.read(File.join(work_dir, "terraform.tfstate"))
    record.terraform_state = state_json
    record.save!
  end
end
