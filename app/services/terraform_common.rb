module TerraformCommon
  private

  def command
    `which terraform`.chomp
  end

  def vars_to_tfvars(vars)
    vars.map { |k, v| "#{k} = \"#{v}\"" }.join("\n")
  end

  def run_cmd(cmd, dir)
    Open3.popen2e(cmd, chdir: dir) do |stdin, stdout_err, wait_thr|
      stdout_err.each do |line|
        broadcast_log(line)
      end

      status = wait_thr.value
      raise "Terraform command failed: #{cmd}" unless status.success?
    end
  end

  def broadcast_log(line)
    ActionCable.server.broadcast("terraform_logs_channel", { message: line })
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
