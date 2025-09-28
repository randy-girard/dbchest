# Load database types module structure
require_relative "../../app/services/database_types/base_database_type"
require_relative "../../app/services/database_types/postgresql_database_type"
require_relative "../../app/services/database_types/mysql_database_type"
require_relative "../../app/services/database_types/mongodb_database_type"
require_relative "../../app/services/database_types/cassandra_database_type"

require_relative "../../app/services/cloud_init_generators/base_cloud_init_generator"
require_relative "../../app/services/cloud_init_generators/postgresql_cloud_init_generator"
require_relative "../../app/services/cloud_init_generators/mysql_cloud_init_generator"
require_relative "../../app/services/cloud_init_generators/mongodb_cloud_init_generator"
require_relative "../../app/services/cloud_init_generators/cassandra_cloud_init_generator"

require_relative "../../app/services/deployment_services/base_deployment_service"
require_relative "../../app/services/deployment_services/postgresql_deployment_service"
require_relative "../../app/services/deployment_services/mysql_deployment_service"
require_relative "../../app/services/deployment_services/mongodb_deployment_service"
require_relative "../../app/services/deployment_services/cassandra_deployment_service"

# Load provider client classes so they can register themselves
require_relative "../../app/models/provider_client/base"
require_relative "../../app/models/provider_client/proxmox"
require_relative "../../app/models/provider_client/digitalocean"
