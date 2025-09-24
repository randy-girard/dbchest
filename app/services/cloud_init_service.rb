require_relative "database_types/base_database_type"

class CloudInitService
  def initialize
  end

  def generate_user_data(node_id, is_replica = false)
    @node = Node.find(node_id)

    # Use the database type strategy pattern to generate the cloud-init script
    database_type_handler = @node.database_type_handler
    return "" unless database_type_handler

    database_type_handler.generate_cloud_init_script(@node, is_replica: is_replica)
  end

  def write_script_to_file(node_id, work_dir, is_replica = false)
    script_content = generate_user_data(node_id, is_replica)
    script_file = File.join(work_dir, "cloud_init_script.sh")

    File.write(script_file, script_content)
    script_file
  end
end
