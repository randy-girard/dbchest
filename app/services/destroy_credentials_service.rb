class DestroyCredentialsService
  include Sidekiq::Job

  def initialize
  end

  def perform(credential_id)
    @credential = Credential.find(credential_id)
    if @credential
      vars = {
        username: @credential.username
      }
      AnsibleRunService.new.perform(@credential.node_id, "destroy_user.yml", vars: vars)
    end
    @credential.destroy!
  end
end
