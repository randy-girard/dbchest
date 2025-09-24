require_relative "deployment_services/postgresql_deployment_service"
require_relative "deployment_services/mysql_deployment_service"

class DatabaseServiceFactory
  # Service registries
  @deployment_services = {}
  @monitoring_services = {}

  def self.register_deployment_service(database_type, service_class)
    @deployment_services[database_type.to_s] = service_class
  end

  def self.register_monitoring_service(database_type, service_class)
    @monitoring_services[database_type.to_s] = service_class
  end

  def self.cloud_init_service_for(node)
    CloudInitService.new
  end

  def self.ansible_service_for(node)
    AnsibleRunService.new
  end

  def self.deployment_service_for(node)
    service_class = @deployment_services[node.database_type_slug]
    if service_class
      service_class.new(node)
    else
      raise ArgumentError, "Unknown database type: #{node.database_type_slug}. Available types: #{@deployment_services.keys.join(', ')}"
    end
  end

  def self.monitoring_service_for(node)
    service_class = @monitoring_services[node.database_type_slug]
    if service_class
      service_class.new(node)
    else
      raise ArgumentError, "Unknown database type: #{node.database_type_slug}. Available types: #{@monitoring_services.keys.join(', ')}"
    end
  end

  def self.registered_deployment_types
    @deployment_services.keys
  end

  def self.registered_monitoring_types
    @monitoring_services.keys
  end
end

# Register existing services
DatabaseServiceFactory.register_deployment_service('postgresql', DeploymentServices::PostgresqlDeploymentService)
DatabaseServiceFactory.register_deployment_service('mysql', DeploymentServices::MysqlDeploymentService)

# Note: Monitoring services would be registered here when they are implemented
# DatabaseServiceFactory.register_monitoring_service('postgresql', DeploymentServices::PostgresqlMonitoringService)
# DatabaseServiceFactory.register_monitoring_service('mysql', DeploymentServices::MysqlMonitoringService)
