module NodesHelper
  def node_form_builder_for_turbo(cluster, node)
    form_with(model: [ cluster, node ]) { |f| return f }
  end
end
