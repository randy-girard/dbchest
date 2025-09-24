require_relative 'deployment_services/postgresql_deployment_service'
require_relative 'deployment_services/mysql_deployment_service'

class DatabaseServiceFactory
  def self.cloud_init_service_for(node)
    CloudInitService.new
  end

  def self.ansible_service_for(node)
    AnsibleRunService.new
  end

  def self.deployment_service_for(node)
    case node.database_type_slug
    when 'postgresql'
      DeploymentServices::PostgresqlDeploymentService.new(node)
    when 'mysql'
      DeploymentServices::MysqlDeploymentService.new(node)
    else
      raise ArgumentError, "Unknown database type: #{node.database_type_slug}"
    end
  end

  def self.monitoring_service_for(node)
    case node.database_type_slug
    when 'postgresql'
      DeploymentServices::PostgresqlMonitoringService.new(node)
    when 'mysql'
      DeploymentServices::MysqlMonitoringService.new(node)
    else
      raise ArgumentError, "Unknown database type: #{node.database_type_slug}"
    end
  end
end
