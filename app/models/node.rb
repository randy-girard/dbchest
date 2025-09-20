class Node < ApplicationRecord
  belongs_to :cluster
  belongs_to :provider
  belongs_to :parent_node, class_name: "Node", optional: true

  has_many :credentials, dependent: :destroy
  has_many :node_settings, dependent: :destroy
  has_many :replicas, class_name: "Node", foreign_key: "parent_node_id", dependent: :destroy
  accepts_nested_attributes_for :node_settings

  validates :name, presence: true, uniqueness: { scope: :cluster_id }
  validate :parent_node_must_be_primary

  # Status constants
  STATUSES = {
    'pending' => 'Pending',
    'provisioning' => 'Provisioning',
    'configuring' => 'Configuring', 
    'active' => 'Active',
    'error' => 'Error',
    'destroying' => 'Destroying',
    'destroyed' => 'Destroyed'
  }.freeze

  validates :status, inclusion: { in: STATUSES.keys }

  # Ensure status is set
  before_validation :set_default_status
  
  # Broadcast status changes
  after_create :broadcast_initial_status
  after_update :broadcast_status_change, if: :saved_change_to_status?

  after_destroy :cleanup_parent_replication_config, if: :replica?

  encrypts :terraform_state,
           :ssh_public_key,
           :ssh_private_key,
           :runtime_config,
           :replication_password

  def build_node_settings!
    provider.provider_type.provider_type_node_options.each do |option|
      unless node_settings.exists?(key: option.key)
        self.node_settings.build(
          provider_type_node_option_id: option.id,
          key: option.key)
      end
    end
  end

  def get_runtime_config_value(key)
    config_entry = runtime_config.fetch(key, {})
    
    # Handle both direct values and Terraform output format
    if config_entry.is_a?(Hash) && config_entry.key?("value")
      # Terraform output format: {"sensitive" => false, "type" => "string", "value" => "actual_value"}
      config_entry.fetch("value", nil)
    elsif config_entry.is_a?(String)
      # Direct string value
      config_entry
    else
      # Other formats or nil
      config_entry
    end
  end

  def get_ip_address
    # First, let's see what's in the runtime_config
    Rails.logger.debug "Node #{id}: Full runtime_config: #{runtime_config.inspect}"
    
    ip_with_subnet = get_runtime_config_value("ip_address")
    
    # Debug logging to help identify the issue
    Rails.logger.debug "Node #{id}: ip_with_subnet from runtime_config: #{ip_with_subnet.inspect}"
    Rails.logger.debug "Node #{id}: ip_with_subnet.nil? = #{ip_with_subnet.nil?}, ip_with_subnet.blank? = #{ip_with_subnet.blank?}"
    
    if ip_with_subnet.nil? || ip_with_subnet.blank?
      Rails.logger.warn "Node #{id}: No IP address found in runtime_config, checking alternative sources"
      
      # Try to get from other runtime config keys that might contain the IP
      alternative_keys = %w[public_ip private_ip ipv4_address external_ip internal_ip vm_ip]
      alternative_keys.each do |key|
        alt_ip = get_runtime_config_value(key)
        if alt_ip.present?
          Rails.logger.debug "Node #{id}: Found IP in alternative key '#{key}': #{alt_ip}"
          ip_with_subnet = alt_ip
          break
        end
      end
      
      # For Proxmox LXC containers, try to extract IP from network interfaces
      if ip_with_subnet.blank?
        network_interfaces = get_runtime_config_value("network_interfaces")
        if network_interfaces.present? && network_interfaces.is_a?(Array)
          Rails.logger.debug "Node #{id}: Checking network interfaces: #{network_interfaces.inspect}"
          network_interfaces.each do |interface|
            if interface.is_a?(Hash) && interface["ip"].present?
              ip_with_subnet = interface["ip"]
              Rails.logger.debug "Node #{id}: Found IP in network interface: #{ip_with_subnet}"
              break
            end
          end
        end
      end
      
      # If still no IP found, return nil which will cause the caller to handle appropriately
      return nil if ip_with_subnet.blank?
    end
    
    # Clean up the IP address
    ip_part = ip_with_subnet.to_s.strip.split('/').first
    
    # Validate it's a proper IP address
    begin
      IPAddr.new(ip_part)
      Rails.logger.debug "Node #{id}: Successfully validated IP address: #{ip_part}"
      return ip_part
    rescue IPAddr::InvalidAddressError => e
      Rails.logger.error "Node #{id}: Invalid IP address '#{ip_part}': #{e.message}"
      
      # If it looks like a hostname, try to resolve it
      if ip_part.match?(/^[a-zA-Z]/)
        begin
          require 'resolv'
          resolved_ip = Resolv.getaddress(ip_part)
          Rails.logger.info "Node #{id}: Resolved hostname '#{ip_part}' to IP: #{resolved_ip}"
          return resolved_ip
        rescue Resolv::ResolvError => resolve_error
          Rails.logger.error "Node #{id}: Failed to resolve hostname '#{ip_part}': #{resolve_error.message}"
        end
      end
      
      # Last resort: return the cleaned value even if it's invalid
      # This will help us see exactly what's being passed to Ansible
      Rails.logger.warn "Node #{id}: Returning potentially invalid IP: '#{ip_part}'"
      return ip_part
    end
  end

  def provider_api_client
    provider.api_client
  end

  def exists_in_provider?
    provider_api_client.exists?(self)
  end

  def provision!
    CreateService.perform_async(id)
  end

  def deprovision!
    DestroyService.perform_async(id)
  end

  def primary?
    parent_node_id.nil?
  end

  def replica?
    parent_node_id.present?
  end

  def has_replicas?
    replicas.any?
  end

  def provision_replica!
    CreateService.perform_async(id, true)
  end

  def ensure_replication_password!
    if replication_password.blank?
      self.replication_password = SecureRandom.alphanumeric(32)
      save!
    end
    replication_password
  end

  def get_replication_password
    primary? ? ensure_replication_password! : parent_node.ensure_replication_password!
  end

  # All nodes are created with replica-ready PostgreSQL configuration by default.
  # This includes WAL level and archive settings.
  # Replication user and pg_hba.conf entries are only created when needed.

  # Status management methods
  def update_status!(new_status, message = nil)
    Rails.logger.info "Updating node #{id} status from '#{status}' to '#{new_status}': #{message}"
    
    if update!(status: new_status)
      Rails.logger.info "Node #{id} status successfully updated to '#{new_status}'"
      broadcast_status_update(message)
    else
      Rails.logger.error "Failed to update node #{id} status to '#{new_status}': #{errors.full_messages.join(', ')}"
    end
  rescue => e
    Rails.logger.error "Error updating node #{id} status: #{e.message}"
    raise e
  end

  def status_display
    STATUSES[status] || status&.humanize || 'Unknown'
  end

  def status_badge_class
    case status
    when 'active'
      'bg-success'
    when 'provisioning', 'configuring'
      'bg-warning'
    when 'error'
      'bg-danger'
    when 'destroying'
      'bg-info'
    when 'destroyed'
      'bg-dark'
    else
      'bg-primary'
    end
  end

  # Ensure we have a status value, fallback for existing nodes
  def status
    read_attribute(:status) || 'pending'
  end

  private

  def set_default_status
    self.status = 'pending' if status.blank?
  end

  def parent_node_must_be_primary
    if parent_node.present? && parent_node.parent_node.present?
      errors.add(:parent_node, "cannot be a replica node. Replicas can only be created from primary nodes.")
    end
  end

  def cleanup_parent_replication_config
    return unless parent_node.present?
    
    # If this was the last replica, optionally clean up replication configuration
    # For now, we'll leave the replication user and password for future use
    # This could be extended to remove pg_hba.conf entries for this specific replica
  end

  def broadcast_initial_status
    broadcast_status_update("Node created")
  end

  def broadcast_status_change
    broadcast_status_update
  end

  def broadcast_status_update(message = nil)
    data = {
      id: id,
      status: status,
      status_display: status_display,
      status_badge_class: status_badge_class,
      name: name,
      message: message,
      updated_at: updated_at.iso8601
    }

    Rails.logger.info "🔊 Broadcasting node status update for node #{id}: #{status} - #{message}"
    Rails.logger.debug "📦 Broadcast data: #{data.inspect}"
    
    # Broadcast to all subscribers
    ActionCable.server.broadcast("node_status_updates", data)
    Rails.logger.info "✅ Broadcasted to stream: node_status_updates"
    
    # Broadcast to specific node subscribers
    ActionCable.server.broadcast("node_status_#{id}", data)
    Rails.logger.info "✅ Broadcasted to stream: node_status_#{id}"
    
    # Broadcast to cluster subscribers
    ActionCable.server.broadcast("cluster_#{cluster_id}_node_status", data)
    Rails.logger.info "✅ Broadcasted to stream: cluster_#{cluster_id}_node_status"
    
    Rails.logger.info "🎯 Total streams broadcasted to: 3"
  rescue => e
    Rails.logger.error "Error broadcasting node status update: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
