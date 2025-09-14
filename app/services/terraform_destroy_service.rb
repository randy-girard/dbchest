class TerraformDestroyService
  include TerraformCommon

  def initialize
  end

  def perform(node_id)
    @node = Node.find(node_id)

    if @node && @node.exists_in_provider?
      begin
        provider_type = @node.provider.provider_type

        # Create isolated working directory for this run
        run_id = SecureRandom.hex(8)
        work_dir = Rails.root.join("tmp", "terraform_runs", run_id)
        FileUtils.mkdir_p(work_dir)

        # Copy Terraform templates into working dir
        provider_key = provider_type.key
        unless ALLOWED_PROVIDER_KEYS.include?(provider_key)
          raise ArgumentError, "Invalid provider type"
        end

        source_dir = Rails.root.join("lib", "terraform", provider_key)
        FileUtils.cp_r("#{source_dir}/.", work_dir)

        vars = @node.provider.terraform_vars
        vars[:ssh_public_key] = @node.ssh_public_key
        vars[:name] = @node.name
                           .to_s
                           .downcase
                           .gsub(/[^a-z0-9]+/, "-")
                           .gsub(/^-+|-+$/, "")

        @node.node_settings.each do |node_setting|
          vars[node_setting.key] = node_setting.value
        end

        # Load state from DB into work dir
        load_state_from_db(work_dir, @node)

        # Write vars file
        File.write(work_dir.join("vars.tfvars"), vars_to_tfvars(vars))

        # Run Terraform commands for destroy
        terraform_cmds = [
          "#{command} init -input=false",
          "#{command} plan -destroy -input=false -var-file=vars.tfvars -out=tfplan",
          "#{command} destroy -input=false -var-file=vars.tfvars -auto-approve"
        ]

        terraform_cmds.each do |cmd|
          run_cmd(cmd, work_dir)
        end

        # Save updated state back to DB (should be empty or updated)
        @node.terraform_state = nil
        @node.save

        # save_state_to_db(work_dir, @node)

      ensure
        # Clean up working directory
        FileUtils.rm_rf(work_dir) if work_dir && Dir.exist?(work_dir)
      end
    end
  end
end
