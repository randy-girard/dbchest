class AnsiblePlaybookService
  def initialize
    @temp_dir = nil
    @temp_files = []
  end

  # Create a temporary directory for Ansible playbooks
  def create_temp_workspace
    return @temp_dir if @temp_dir

    @temp_dir = Dir.mktmpdir("ansible_playbooks_")
    Rails.logger.info "Created temporary Ansible workspace: #{@temp_dir}"
    @temp_dir
  end

  # Write a playbook to the temporary workspace
  def write_playbook(name, content, variables = {})
    ensure_temp_workspace_exists
    
    # Process template variables in content
    processed_content = process_template_variables(content, variables)
    
    # Create the playbook file
    playbook_path = File.join(@temp_dir, "#{name}.yml")
    File.write(playbook_path, processed_content)
    
    # Track the file for cleanup
    @temp_files << playbook_path
    
    Rails.logger.info "Created playbook: #{playbook_path}"
    playbook_path
  end

  # Write a playbook from an existing template file
  def write_playbook_from_template(template_path, name, variables = {})
    template_content = File.read(Rails.root.join(template_path))
    write_playbook(name, template_content, variables)
  end

  # Create an inventory file
  def write_inventory(hosts_config)
    ensure_temp_workspace_exists
    
    inventory_path = File.join(@temp_dir, "inventory")
    inventory_content = generate_inventory_content(hosts_config)
    
    File.write(inventory_path, inventory_content)
    @temp_files << inventory_path
    
    Rails.logger.info "Created inventory: #{inventory_path}"
    inventory_path
  end

  # Create a variables file
  def write_vars_file(variables)
    ensure_temp_workspace_exists
    
    vars_path = File.join(@temp_dir, "vars.yml")
    vars_content = variables.to_yaml
    
    File.write(vars_path, vars_content)
    @temp_files << vars_path
    
    Rails.logger.info "Created vars file: #{vars_path}"
    vars_path
  end

  # Clean up all temporary files and directory
  def cleanup!
    return unless @temp_dir

    begin
      # Remove individual files first
      @temp_files.each do |file_path|
        File.delete(file_path) if File.exist?(file_path)
      end

      # Remove the temporary directory
      FileUtils.remove_entry(@temp_dir) if Dir.exist?(@temp_dir)
      
      Rails.logger.info "Cleaned up temporary Ansible workspace: #{@temp_dir}"
    rescue => e
      Rails.logger.error "Failed to cleanup Ansible workspace #{@temp_dir}: #{e.message}"
    ensure
      @temp_dir = nil
      @temp_files.clear
    end
  end

  # Get the path to the temporary workspace
  def workspace_path
    @temp_dir
  end

  private

  def ensure_temp_workspace_exists
    create_temp_workspace unless @temp_dir
  end

  def process_template_variables(content, variables)
    processed_content = content.dup
    
    variables.each do |key, value|
      # Handle both {{ key }} and {{key}} formats
      processed_content.gsub!(/\{\{\s*#{Regexp.escape(key.to_s)}\s*\}\}/, value.to_s)
    end
    
    processed_content
  end

  def generate_inventory_content(hosts_config)
    content = []
    
    hosts_config.each do |group_name, hosts|
      content << "[#{group_name}]"
      
      hosts.each do |host|
        host_line = host[:ip]
        host_line += " ansible_user=#{host[:user]}" if host[:user]
        host_line += " ansible_ssh_private_key_file=#{host[:ssh_key]}" if host[:ssh_key]
        host_line += " ansible_ssh_common_args='-o StrictHostKeyChecking=no'" if host[:skip_host_check]
        
        content << host_line
      end
      
      content << "" # Empty line between groups
    end
    
    content.join("\n")
  end
end
