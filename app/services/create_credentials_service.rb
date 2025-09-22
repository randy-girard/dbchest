require "securerandom"

class CreateCredentialsService
  include Sidekiq::Job

  def initialize
  end

  def perform(credential_id)
    @credential = Credential.find(credential_id)
    if @credential
      @credential.password = SecureRandom.hex(16)
      @credential.save

      vars = {
        username: @credential.username,
        password: @credential.password,
        postgresql_version: @credential.node.database_type_version&.version || '15'
      }
      AnsibleRunService.new.perform(@credential.node_id, "create_user.yml", vars: vars)
    end
  end
end
