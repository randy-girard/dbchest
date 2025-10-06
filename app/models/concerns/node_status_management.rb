# frozen_string_literal: true

# Concern for managing node status and broadcasting status changes
module NodeStatusManagement
  extend ActiveSupport::Concern

  included do
    # Status constants
    STATUSES = {
      "pending" => "Pending",
      "provisioning" => "Provisioning",
      "configuring" => "Configuring",
      "active" => "Active",
      "error" => "Error",
      "destroying" => "Destroying",
      "destroyed" => "Destroyed"
    }.freeze

    validates :status, inclusion: { in: STATUSES.keys }

    # Callbacks
    before_validation :set_default_status
    after_create :broadcast_initial_status
    after_update :broadcast_status_change, if: :saved_change_to_status?
    after_update :provision_default_credential, if: :should_provision_default_credential?
  end

  # Status query methods
  def active?
    status == "active"
  end

  def pending?
    status == "pending"
  end

  def provisioning?
    status == "provisioning"
  end

  def error?
    status == "error"
  end

  def destroying?
    status == "destroying"
  end

  # def destroyed?
  #  status == "destroyed"
  # end

  # Status management methods
  def update_status!(new_status, message = nil)
    Rails.logger.info "Updating node #{id} status from '#{status}' to '#{new_status}': #{message}"

    if update!(status: new_status)
      Rails.logger.info "Node #{id} status successfully updated to '#{new_status}'"
      broadcast_status_update(message)
      broadcast_to_development_console("node_update_status", message) if Rails.env.development?
    else
      Rails.logger.error "Failed to update node #{id} status to '#{new_status}': #{errors.full_messages.join(', ')}"
    end
  rescue => e
    puts e.backtrace.join("\n")
    Rails.logger.error "Error updating node #{id} status: #{e.message}"
    raise e
  end

  def status_display
    STATUSES[status] || status&.humanize || "Unknown"
  end

  def status_badge_class
    case status
    when "active"
      "bg-success"
    when "provisioning", "configuring"
      "bg-warning"
    when "error"
      "bg-danger"
    when "destroying"
      "bg-info"
    when "destroyed"
      "bg-dark"
    else
      "bg-primary"
    end
  end

  # Ensure we have a status value, fallback for existing nodes
  def status
    read_attribute(:status) || "pending"
  end

  private

  def set_default_status
    self.status = "pending" if status.blank?
  end

  def broadcast_initial_status
    broadcast_status_update("Node created")
  end

  def broadcast_status_change
    broadcast_status_update
  end

  def broadcast_status_update(message = nil)
    data = build_broadcast_data(message)

    Rails.logger.info "🔊 Broadcasting node status update for node #{id}: #{status} - #{message}"
    Rails.logger.debug "📦 Broadcast data: #{data.inspect}"

    broadcast_to_channels(data)
    broadcast_to_development_console("node_status_update", message, data) if Rails.env.development?

    Rails.logger.info "🎯 Total streams broadcasted to: #{Rails.env.development? ? 4 : 3}"
  rescue => e
    Rails.logger.error "Error broadcasting node status update: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def build_broadcast_data(message)
    data = {
      id: id,
      status: status,
      status_display: status_display,
      status_badge_class: status_badge_class,
      name: name,
      message: message,
      updated_at: updated_at.iso8601
    }

    # Include error details if available
    data[:error_details] = error_details if error_details.present?

    data
  end

  def broadcast_to_channels(data)
    # Broadcast to all subscribers
    ActionCable.server.broadcast("node_status_updates", data)
    Rails.logger.info "✅ Broadcasted to stream: node_status_updates"

    # Broadcast to specific node subscribers
    ActionCable.server.broadcast("node_status_#{id}", data)
    Rails.logger.info "✅ Broadcasted to stream: node_status_#{id}"

    # Broadcast to cluster subscribers
    ActionCable.server.broadcast("cluster_#{cluster_id}_node_status", data)
    Rails.logger.info "✅ Broadcasted to stream: cluster_#{cluster_id}_node_status"
  end

  def broadcast_to_development_console(event_type, message, additional_data = {})
    console_data = {
      timestamp: Time.current.strftime("%H:%M:%S"),
      event_type: event_type,
      message: message,
      node_name: name,
      cluster_id: cluster_id
    }.merge(additional_data)

    ActionCable.server.broadcast("development_console", console_data)
    Rails.logger.debug "🖥️  Broadcasted to development console: #{console_data.inspect}"
  end

  def should_provision_default_credential?
    # Only provision for primary nodes that just became active
    return false unless primary?
    return false unless saved_change_to_status?
    return false unless status == "active"

    # Check if status changed TO active (not just updated while already active)
    status_before, status_after = saved_change_to_status
    status_before != "active" && status_after == "active"
  end

  def provision_default_credential
    Rails.logger.info "Node #{id} became active - queueing default credential provisioning"
    ProvisionDefaultCredentialJob.perform_later(id)
  end
end
