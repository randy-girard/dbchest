# frozen_string_literal: true

# Concern for managing node IP address extraction and validation
module NodeIpAddressManagement
  extend ActiveSupport::Concern

  ALTERNATIVE_IP_KEYS = %w[public_ip private_ip ipv4_address external_ip internal_ip vm_ip].freeze

  def get_ip_address
    Rails.logger.debug "Node #{id}: Full runtime_config: #{runtime_config.inspect}"

    ip_with_subnet = extract_ip_from_runtime_config
    return nil if ip_with_subnet.blank?

    clean_and_validate_ip(ip_with_subnet)
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

  private

  def extract_ip_from_runtime_config
    ip_with_subnet = get_runtime_config_value("ip_address")

    Rails.logger.debug "Node #{id}: ip_with_subnet from runtime_config: #{ip_with_subnet.inspect}"

    if ip_with_subnet.blank?
      Rails.logger.warn "Node #{id}: No IP address found in runtime_config, checking alternative sources"
      ip_with_subnet = check_alternative_ip_sources
    end

    ip_with_subnet
  end

  def check_alternative_ip_sources
    # Try alternative keys
    ip_from_keys = check_alternative_keys
    return ip_from_keys if ip_from_keys.present?

    # Try network interfaces
    check_network_interfaces
  end

  def check_alternative_keys
    ALTERNATIVE_IP_KEYS.each do |key|
      alt_ip = get_runtime_config_value(key)
      if alt_ip.present?
        Rails.logger.debug "Node #{id}: Found IP in alternative key '#{key}': #{alt_ip}"
        return alt_ip
      end
    end
    nil
  end

  def check_network_interfaces
    network_interfaces = get_runtime_config_value("network_interfaces")
    return nil unless network_interfaces.present? && network_interfaces.is_a?(Array)

    Rails.logger.debug "Node #{id}: Checking network interfaces: #{network_interfaces.inspect}"

    network_interfaces.each do |interface|
      if interface.is_a?(Hash) && interface["ip"].present?
        Rails.logger.debug "Node #{id}: Found IP in network interface: #{interface['ip']}"
        return interface["ip"]
      end
    end

    nil
  end

  def clean_and_validate_ip(ip_with_subnet)
    # Clean up the IP address (remove subnet mask if present)
    ip_part = ip_with_subnet.to_s.strip.split("/").first

    validate_ip_address(ip_part)
  end

  def validate_ip_address(ip_part)
    IPAddr.new(ip_part)
    Rails.logger.debug "Node #{id}: Successfully validated IP address: #{ip_part}"
    ip_part
  rescue IPAddr::InvalidAddressError => e
    Rails.logger.error "Node #{id}: Invalid IP address '#{ip_part}': #{e.message}"
    attempt_hostname_resolution(ip_part)
  end

  def attempt_hostname_resolution(ip_part)
    # If it looks like a hostname, try to resolve it
    if ip_part.match?(/^[a-zA-Z]/)
      resolve_hostname(ip_part)
    else
      # Last resort: return the cleaned value even if it's invalid
      Rails.logger.warn "Node #{id}: Returning potentially invalid IP: '#{ip_part}'"
      ip_part
    end
  end

  def resolve_hostname(hostname)
    require "resolv"
    resolved_ip = Resolv.getaddress(hostname)
    Rails.logger.info "Node #{id}: Resolved hostname '#{hostname}' to IP: #{resolved_ip}"
    resolved_ip
  rescue Resolv::ResolvError => e
    Rails.logger.error "Node #{id}: Failed to resolve hostname '#{hostname}': #{e.message}"
    Rails.logger.warn "Node #{id}: Returning potentially invalid IP: '#{hostname}'"
    hostname
  end
end
