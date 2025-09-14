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
        password: @credential.password
      }
      AnsibleRunService.new.perform(@credential.node_id, "create_user.yml", vars: vars)
    end
  end
end
