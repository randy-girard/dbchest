class TerraformBaseService
  include TerraformCommon

  def initialize
  end

  protected

  def setup_working_directory(node, operation_type)
    run_id = SecureRandom.hex(8)
    work_dir = Rails.root.join("tmp", "terraform_runs", run_id)
    FileUtils.mkdir_p(work_dir)

    terraform_log_path = terraform_log_file_path(node.id, run_id)
    Rails.logger.info "Terraform #{operation_type} logs will be written to: #{terraform_log_path}"

    { work_dir: work_dir, run_id: run_id, terraform_log_path: terraform_log_path }
  end

  def copy_terraform_templates(work_dir, provider_type)
    provider_key = provider_type.key
    unless ALLOWED_PROVIDER_KEYS.include?(provider_key)
      raise ArgumentError, "Invalid provider type: #{provider_key}"
    end

    source_dir = Rails.root.join("lib", "terraform", provider_key)
    FileUtils.cp_r("#{source_dir}/.", work_dir)
  end

  def prepare_terraform_vars(node)
    vars = {}

    # Provider configuration
    provider_config = node.provider.terraform_vars.dup
    provider_config.each do |key, value|
      vars[key.to_sym] = value
    end

    # Node-specific credentials
    vars[:ssh_public_key] = node.ssh_public_key
    vars[:ssh_private_key] = node.ssh_private_key
    vars[:name] = normalize_node_name(node.name)

    # Database type and version information
    vars[:database_type] = node.database_type_slug
    vars[:database_version] = node.database_version
    vars[:node_id] = node.id.to_s
    vars[:is_replica] = node.replica?
    vars[:primary_node_ip] = node.parent_node&.get_ip_address || ""

    # Node settings
    add_node_settings_to_vars(vars, node)

    vars
  end

  def normalize_node_name(name)
    name.to_s
        .downcase
        .gsub(/[^a-z0-9]+/, "-")
        .gsub(/^-+|-+$/, "")
  end

  def add_node_settings_to_vars(vars, node)
    network_config = {}
    subnet_id = nil
    bridge = "vmbr0" # default

    node.node_settings.each do |node_setting|
      vars[node_setting.key] = node_setting.value

      # Extract network-related settings for network_config
      case node_setting.key
      when "network", "subnet"
        subnet_id = node_setting.value
      when "bridge"
        bridge = node_setting.value
      end
    end

    # Set network_config if we have subnet information
    if subnet_id.present?
      vars[:network_config] = {
        subnet_id: subnet_id,
        bridge: bridge
      }
    end
  end

  def execute_terraform_commands(commands, work_dir, terraform_log_path)
    commands.each do |cmd|
      run_cmd(cmd, work_dir, terraform_log_path)
    end
  end

  def cleanup_on_success(work_dir)
    FileUtils.rm_rf(work_dir) if work_dir && Dir.exist?(work_dir)
  end

  def preserve_on_failure(work_dir, operation_type, error)
    Rails.logger.error "Terraform #{operation_type} failed. Working directory preserved at: #{work_dir}"
    Rails.logger.error "Error: #{error.message}"
    raise error
  end

  def log_completion(operation_type, terraform_log_path)
    Rails.logger.info "Terraform #{operation_type} completed. Full logs available at: #{terraform_log_path}"
  end
end
