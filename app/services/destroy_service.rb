class DestroyService
  include Sidekiq::Job

  def initialize
  end

  def perform(node_id)
    @node = Node.find_by_id(node_id)

    TerraformDestroyService.new.perform(@node.id)

    @node.destroy!
  end
end
