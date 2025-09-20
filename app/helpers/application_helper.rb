module ApplicationHelper
  def node_status_display(node)
    status = node.status || 'pending'
    status.humanize
  end
  
  def node_status_badge_class(node)
    status = node.status || 'pending'
    case status
    when 'active', 'running'
      'badge bg-success'
    when 'pending', 'creating', 'provisioning'
      'badge bg-warning'
    when 'destroying', 'stopping'
      'badge bg-info'
    when 'error', 'failed'
      'badge bg-danger'
    when 'destroyed'
      'badge bg-dark'
    else
      'badge bg-primary'
    end
  end
end
