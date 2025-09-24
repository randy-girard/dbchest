class Credential < ApplicationRecord
  belongs_to :node

  validates :username, presence: true

  encrypts :username,
           :password

  def provision!
    CreateCredentialsService.perform_async(id)
  end

  def deprovision!
    DestroyCredentialsService.perform_async(id)
  end
end
