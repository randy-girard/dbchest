class TerraformDestroyService < TerraformBaseService
  def perform(node_id)
    @node = Node.find(node_id)
    return unless @node && @node.exists_in_provider?

    begin
      # Setup working environment
      env = setup_working_directory(@node, "destroy")
      work_dir = env[:work_dir]
      terraform_log_path = env[:terraform_log_path]

      # Copy Terraform templates
      copy_terraform_templates(work_dir, @node.provider.provider_type)

      # Prepare variables (simpler for destroy)
      vars = prepare_destroy_vars(@node)

      # Load state from DB into work dir
      load_state_from_db(work_dir, @node)

      # Write vars file
      File.write(work_dir.join("vars.tfvars"), vars_to_tfvars(vars))

      # Execute Terraform destroy commands
      terraform_cmds = [
        "#{command} init -input=false",
        "#{command} plan -destroy -input=false -var-file=vars.tfvars -out=tfplan",
        "#{command} destroy -input=false -var-file=vars.tfvars -auto-approve"
      ]

      execute_terraform_commands(terraform_cmds, work_dir, terraform_log_path)

      # Clear state after successful destroy
      @node.terraform_state = nil
      @node.save

      log_completion("destroy", terraform_log_path)
      cleanup_on_success(work_dir)

    rescue => e
      preserve_on_failure(work_dir, "destroy", e)
    end
  end

  private

  def prepare_destroy_vars(node)
    vars = node.provider.terraform_vars.dup
    vars[:ssh_public_key] = node.ssh_public_key
    vars[:ssh_private_key] = node.ssh_private_key
    vars[:name] = normalize_node_name(node.name)

    node.node_settings.each do |node_setting|
      vars[node_setting.key] = node_setting.value
    end

    vars
  end
end
