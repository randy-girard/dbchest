require "net/ssh"
require "tempfile"

class NodeLogFetcherService
  LOG_FILE_PATH = "/var/log/dbchest-setup.log"

  def initialize(node)
    @node = node
  end

  def fetch_and_parse_logs
    return { success: false, error: "Node has no IP address" } unless @node.get_ip_address.present?

    log_content = fetch_log_file

    return { success: false, error: "Could not retrieve log file" } unless log_content

    parsed_errors = parse_errors_from_log(log_content)
    compatibility_error = detect_compatibility_error(log_content)

    {
      success: true,
      log_content: log_content,
      parsed_errors: parsed_errors,
      compatibility_error: compatibility_error,
      error_summary: build_error_summary(parsed_errors, compatibility_error)
    }
  rescue => e
    Rails.logger.error "Error fetching logs for node #{@node.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: e.message }
  end

  def fetch_and_store_error_details
    result = fetch_and_parse_logs

    if result[:success] && result[:error_summary].present?
      @node.update_column(:error_details, result[:error_summary])

      # Broadcast the error details to the UI
      @node.broadcast_status_update(result[:error_summary])

      Rails.logger.info "Stored error details for node #{@node.id}: #{result[:error_summary]}"
    end

    result
  end

  private

  def fetch_log_file
    ip_address = @node.get_ip_address

    Rails.logger.info "Fetching cloud-init logs from #{ip_address}..."

    # Create temporary file for SSH key
    key_file = Tempfile.new([ "ssh_key", ".pem" ])
    key_file.write(@node.ssh_private_key)
    key_file.chmod(0600)
    key_file.flush
    key_file.close

    log_content = nil

    Net::SSH.start(ip_address, "root",
                   keys: [ key_file.path ],
                   timeout: 10,
                   non_interactive: true,
                   verify_host_key: :never) do |ssh|
      # Check if log file exists
      result = ssh.exec!("test -f #{LOG_FILE_PATH} && echo 'exists' || echo 'missing'")

      if result.strip == "missing"
        Rails.logger.warn "Log file not found on node #{@node.id}"
        return nil
      end

      # Fetch the log file
      log_content = ssh.exec!("cat #{LOG_FILE_PATH}")
      Rails.logger.info "Retrieved #{log_content.lines.count} lines of logs from node #{@node.id}"
    end

    key_file.unlink
    log_content

  rescue Net::SSH::AuthenticationFailed => e
    Rails.logger.error "SSH authentication failed for node #{@node.id}: #{e.message}"
    nil
  rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, Net::SSH::ConnectionTimeout => e
    Rails.logger.error "Could not connect to node #{@node.id}: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "Error fetching log file from node #{@node.id}: #{e.message}"
    nil
  end

  def parse_errors_from_log(log_content)
    return [] if log_content.blank?

    errors = []

    log_content.each_line do |line|
      # Look for ERROR lines, FAILED messages, or other error indicators
      if line.match?(/ERROR:|FAILED|error:|E: Unable to locate package|E: Package/)
        errors << line.strip
      end
    end

    # Return last 20 error lines to avoid overwhelming the UI
    errors.last(20)
  end

  def detect_compatibility_error(log_content)
    return nil if log_content.blank?

    # Pattern 1: PostgreSQL version not available for Ubuntu version
    if log_content.match?(/E: Unable to locate package postgresql-(\d+)/)
      pg_version = log_content.match(/E: Unable to locate package postgresql-(\d+)/)[1]
      ubuntu_version = detect_ubuntu_version(log_content)

      return {
        type: "version_compatibility",
        database: "PostgreSQL",
        database_version: pg_version,
        os_version: ubuntu_version,
        message: build_compatibility_message("PostgreSQL", pg_version, ubuntu_version)
      }
    end

    # Pattern 2: MySQL version not available
    if log_content.match?(/E: Unable to locate package mysql-server-(\d+\.\d+)/)
      mysql_version = log_content.match(/E: Unable to locate package mysql-server-(\d+\.\d+)/)[1]
      ubuntu_version = detect_ubuntu_version(log_content)

      return {
        type: "version_compatibility",
        database: "MySQL",
        database_version: mysql_version,
        os_version: ubuntu_version,
        message: build_compatibility_message("MySQL", mysql_version, ubuntu_version)
      }
    end

    # Pattern 3: Generic package not found errors
    if log_content.match?(/E: Unable to locate package/)
      package_name = log_content.match(/E: Unable to locate package (\S+)/)[1]

      return {
        type: "package_not_found",
        package: package_name,
        message: "Package '#{package_name}' could not be found. This may indicate a version compatibility issue."
      }
    end

    nil
  end

  def detect_ubuntu_version(log_content)
    # Try to find Ubuntu version from logs
    if log_content.match?(/Ubuntu (\d+\.\d+)/)
      return log_content.match(/Ubuntu (\d+\.\d+)/)[1]
    end

    # Fallback: try to detect from codename
    if log_content.match?(/(focal|jammy|noble)/)
      codename = log_content.match(/(focal|jammy|noble)/)[1]
      case codename
      when "focal"
        return "20.04"
      when "jammy"
        return "22.04"
      when "noble"
        return "24.04"
      end
    end

    "Unknown"
  end

  def build_compatibility_message(database, version, ubuntu_version)
    case database
    when "PostgreSQL"
      if version.to_i >= 16 && ubuntu_version == "20.04"
        "PostgreSQL #{version} requires Ubuntu 22.04 or later. This node is running Ubuntu #{ubuntu_version}. Please use PostgreSQL 15 or earlier, or upgrade to Ubuntu 22.04+."
      else
        "PostgreSQL #{version} is not compatible with Ubuntu #{ubuntu_version}. Please check the PostgreSQL documentation for supported Ubuntu versions."
      end
    when "MySQL"
      "MySQL #{version} is not available for Ubuntu #{ubuntu_version}. Please check the MySQL documentation for supported Ubuntu versions."
    else
      "#{database} #{version} may not be compatible with Ubuntu #{ubuntu_version}."
    end
  end

  def build_error_summary(parsed_errors, compatibility_error)
    summary_parts = []

    if compatibility_error
      summary_parts << "⚠️ VERSION COMPATIBILITY ISSUE: #{compatibility_error[:message]}"
    end

    if parsed_errors.any?
      summary_parts << "\nRecent errors from installation log:"
      summary_parts << parsed_errors.last(5).join("\n")
    end

    summary_parts.join("\n").strip
  end
end
