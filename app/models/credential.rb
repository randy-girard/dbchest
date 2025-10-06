class Credential < ApplicationRecord
  belongs_to :node

  validates :username, presence: true
  validate :username_cannot_be_changed, on: :update
  validate :password_cannot_be_changed, on: :update

  encrypts :username,
           :password

  # Attribute to allow bypassing deletion protection
  attr_accessor :skip_default_credential_protection

  # Prevent deletion of default credential
  before_destroy :prevent_default_credential_deletion, unless: :skip_default_credential_protection

  def provision!
    CreateCredentialsService.perform_async(id)
  end

  def deprovision!
    DestroyCredentialsService.perform_async(id)
  end

  def default_credential?
    username == "default"
  end

  # Connection string helpers
  def connection_strings
    return {} unless node&.active?

    ip_address = node.get_ip_address
    return {} unless ip_address

    database_type = node.database_type_slug
    port = node.database_type_version&.default_port

    case database_type
    when "postgresql"
      postgresql_connection_strings(ip_address, port)
    when "mysql"
      mysql_connection_strings(ip_address, port)
    when "mongodb"
      mongodb_connection_strings(ip_address, port)
    when "cassandra"
      cassandra_connection_strings(ip_address, port)
    else
      {}
    end
  end

  private

  def postgresql_connection_strings(ip_address, port)
    {
      psql: "psql -h #{ip_address} -p #{port} -U #{username} -d postgres",
      uri: "postgresql://#{username}:#{password}@#{ip_address}:#{port}/postgres",
      jdbc: "jdbc:postgresql://#{ip_address}:#{port}/postgres?user=#{username}&password=#{password}",
      connection_string: "host=#{ip_address} port=#{port} user=#{username} password=#{password} dbname=postgres",
      rails: {
        adapter: "postgresql",
        host: ip_address,
        port: port,
        username: username,
        password: password,
        database: "postgres"
      }
    }
  end

  def mysql_connection_strings(ip_address, port)
    {
      mysql: "mysql -h #{ip_address} -P #{port} -u #{username} -p#{password}",
      uri: "mysql://#{username}:#{password}@#{ip_address}:#{port}/",
      jdbc: "jdbc:mysql://#{ip_address}:#{port}/?user=#{username}&password=#{password}",
      connection_string: "server=#{ip_address};port=#{port};uid=#{username};pwd=#{password}",
      rails: {
        adapter: "mysql2",
        host: ip_address,
        port: port,
        username: username,
        password: password
      }
    }
  end

  def mongodb_connection_strings(ip_address, port)
    {
      mongo: "mongosh \"mongodb://#{username}:#{password}@#{ip_address}:#{port}/admin\"",
      uri: "mongodb://#{username}:#{password}@#{ip_address}:#{port}/admin",
      connection_string: "mongodb://#{username}:#{password}@#{ip_address}:#{port}/admin?authSource=admin",
      rails: {
        adapter: "mongoid",
        hosts: [ "#{ip_address}:#{port}" ],
        database: "admin",
        options: {
          user: username,
          password: password,
          auth_source: "admin"
        }
      }
    }
  end

  def cassandra_connection_strings(ip_address, port)
    {
      cqlsh: "cqlsh #{ip_address} #{port} -u #{username} -p #{password}",
      connection_string: "contact_points=#{ip_address};port=#{port};username=#{username};password=#{password}",
      driver: {
        contact_points: [ ip_address ],
        port: port,
        username: username,
        password: password
      }
    }
  end

  def prevent_default_credential_deletion
    if default_credential?
      errors.add(:base, "Cannot delete the default credential")
      throw(:abort)
    end
  end

  def username_cannot_be_changed
    if username_changed? && persisted?
      errors.add(:username, "cannot be changed after creation")
    end
  end

  def password_cannot_be_changed
    if password_changed? && persisted?
      errors.add(:password, "cannot be changed after creation")
    end
  end
end
