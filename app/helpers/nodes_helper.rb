module NodesHelper
  def node_form_builder_for_turbo(cluster, node)
    form_with(model: [ cluster, node ]) { |f| return f }
  end

  def node_status_badge(node, options = {})
    css_classes = "badge #{node.status_badge_class}"
    css_classes += " #{options[:class]}" if options[:class]

    content_tag :span,
                node.status_display,
                class: css_classes,
                "data-node-status" => node.id,
                "data-initial-status" => node.status
  end

  def node_status_message_area(node, options = {})
    css_classes = "status-message text-muted small"
    css_classes += " #{options[:class]}" if options[:class]

    content_tag :div,
                "",
                class: css_classes,
                "data-node-status-message" => node.id,
                style: "display: none;"
  end
end
