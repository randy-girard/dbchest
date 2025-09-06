class CreateService
  def initialize
  end

  def perform(node_id)
    @node = Node.find_by_id(node_id)

    TerraformCreateService.new.perform(@node.id)

    AnsibleRunService.new.perform(@node.id)
  end
end
