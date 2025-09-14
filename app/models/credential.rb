class Credential < ApplicationRecord
  belongs_to :node

  encrypts :username,
           :password

  def provision!
    CreateCredentialsService.perform_async(id)
  end

  def deprovision!
    DestroyCredentialsService.perform_async(id)
  end
end
