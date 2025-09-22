module TerraformCommon
  ALLOWED_PROVIDER_KEYS = %w[aws linode proxmox gcp azure].freeze

  private

  def command
    `which terraform`.chomp
  end

  def vars_to_tfvars(vars)
    vars.map do |k, v| 
      # Don't escape base64-encoded cloud_init_user_data, it only contains safe characters
      if k.to_s == 'cloud_init_user_data' && v.to_s.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)
        # Base64 string - no escaping needed
        "#{k} = \"#{v}\""
      else
        # Escape quotes, backslashes, and newlines for all other strings
        escaped_v = v.to_s.gsub('\\', '\\\\').gsub('"', '\\"').gsub("\n", '\\n').gsub("\r", '\\r')
        "#{k} = \"#{escaped_v}\""
      end
    end.join("\n")
  end

  def run_cmd(cmd, dir)
    Open3.popen2e(cmd, chdir: dir) do |stdin, stdout_err, wait_thr|
      stdout_err.each do |line|
        line.chomp!
        Rails.logger.info line
        broadcast_log(line)
      end

      status = wait_thr.value
      raise "Terraform command failed: #{cmd}" unless status.success?
    end
  end

  def broadcast_log(line)
    ActionCable.server.broadcast("terraform_logs_channel", { message: line })
    
    # In development, also broadcast to console channel for debugging
    if Rails.env.development?
      console_data = {
        timestamp: Time.current.strftime("%H:%M:%S"),
        event_type: 'terraform_log',
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
