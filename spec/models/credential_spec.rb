require 'rails_helper'

RSpec.describe Credential, type: :model do
  let(:database_type) { create(:database_type, :with_versions) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type.database_type_versions.first) }
  let(:credential) { build(:credential, node: node) }

  describe 'associations' do
    it { should belong_to(:node) }
  end

  describe 'encryption' do
    it 'encrypts username and password' do
      credential.save!

      # Check that the raw database values are encrypted (not the same as the original)
      raw_record = Credential.connection.select_one(
        "SELECT username, password FROM credentials WHERE id = #{credential.id}"
      )

      expect(raw_record['username']).not_to eq(credential.username)
      expect(raw_record['password']).not_to eq(credential.password)
    end

    it 'decrypts username and password when accessed' do
      original_username = credential.username
      original_password = credential.password

      credential.save!
      credential.reload

      expect(credential.username).to eq(original_username)
      expect(credential.password).to eq(original_password)
    end
  end

  describe '#provision!' do
    it 'calls CreateCredentialsService.perform_async' do
      credential.save!
      expect(CreateCredentialsService).to receive(:perform_async).with(credential.id)
      credential.provision!
    end
  end

  describe '#deprovision!' do
    it 'calls DestroyCredentialsService.perform_async' do
      credential.save!
      expect(DestroyCredentialsService).to receive(:perform_async).with(credential.id)
      credential.deprovision!
    end
  end

  describe 'factory' do
    it 'creates a valid credential' do
      expect(credential).to be_valid
    end

    it 'creates admin credential with trait' do
      admin_credential = build(:credential, :admin, node: node)
      expect(admin_credential.username).to eq('admin')
    end

    it 'creates readonly credential with trait' do
      readonly_credential = build(:credential, :readonly, node: node)
      expect(readonly_credential.username).to eq('readonly')
    end
  end
end
