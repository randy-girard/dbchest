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

  describe '#default_credential?' do
    it 'returns true when username is "default"' do
      credential.username = 'default'
      expect(credential.default_credential?).to be true
    end

    it 'returns false when username is not "default"' do
      credential.username = 'admin'
      expect(credential.default_credential?).to be false
    end
  end

  describe 'immutability validations' do
    context 'when updating username' do
      it 'prevents username changes on persisted records' do
        credential.save!
        credential.username = 'newusername'
        expect(credential.valid?).to be false
        expect(credential.errors[:username]).to include("cannot be changed after creation")
      end

      it 'allows username to be set on new records' do
        new_credential = build(:credential, node: node, username: 'testuser', password: 'password')
        expect(new_credential.valid?).to be true
      end
    end

    context 'when updating password' do
      it 'prevents password changes on persisted records' do
        credential.save!
        credential.password = 'newpassword'
        expect(credential.valid?).to be false
        expect(credential.errors[:password]).to include("cannot be changed after creation")
      end

      it 'allows password to be set on new records' do
        new_credential = build(:credential, node: node, username: 'testuser', password: 'password')
        expect(new_credential.valid?).to be true
      end
    end
  end

  describe 'deletion protection' do
    context 'when credential is default' do
      let(:default_credential) { create(:credential, node: node, username: 'default', password: 'password') }

      it 'prevents deletion when deleted directly' do
        default_credential.save!
        expect { default_credential.destroy }.not_to change { Credential.count }
      end

      it 'adds error to base when deleted directly' do
        default_credential.save!
        default_credential.destroy
        expect(default_credential.errors[:base]).to include("Cannot delete the default credential")
      end

      it 'allows deletion when node is being destroyed' do
        default_credential.save!
        expect { node.destroy }.to change { Credential.count }.by(-1)
      end

      it 'allows deletion when skip_default_credential_protection is set' do
        default_credential.save!
        default_credential.skip_default_credential_protection = true
        expect { default_credential.destroy }.to change { Credential.count }.by(-1)
      end
    end

    context 'when credential is not default' do
      it 'allows deletion' do
        credential.save!
        expect { credential.destroy }.to change { Credential.count }.by(-1)
      end
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

  describe '#connection_strings' do
    let(:active_node) { create(:node, :active, cluster: cluster, provider: provider, database_type_version: database_type.database_type_versions.first) }
    let(:active_credential) { create(:credential, node: active_node, username: 'testuser', password: 'testpass') }

    before do
      allow(active_node).to receive(:get_ip_address).and_return('192.168.1.100')
    end

    context 'with inactive node' do
      it 'returns empty hash' do
        inactive_credential = create(:credential, node: node)
        expect(inactive_credential.connection_strings).to eq({})
      end
    end

    context 'with node without IP address' do
      it 'returns empty hash' do
        allow(active_node).to receive(:get_ip_address).and_return(nil)
        expect(active_credential.connection_strings).to eq({})
      end
    end

    context 'with PostgreSQL node' do
      before do
        allow(active_node).to receive(:database_type_slug).and_return('postgresql')
        allow(active_node.database_type_version).to receive(:default_port).and_return(5432)
      end

      it 'returns PostgreSQL connection strings' do
        strings = active_credential.connection_strings

        expect(strings[:psql]).to eq('psql -h 192.168.1.100 -p 5432 -U testuser -d postgres')
        expect(strings[:uri]).to eq('postgresql://testuser:testpass@192.168.1.100:5432/postgres')
        expect(strings[:jdbc]).to include('jdbc:postgresql://')
        expect(strings[:connection_string]).to include('host=192.168.1.100')
        expect(strings[:rails]).to be_a(Hash)
        expect(strings[:rails][:adapter]).to eq('postgresql')
      end
    end

    context 'with MySQL node' do
      before do
        allow(active_node).to receive(:database_type_slug).and_return('mysql')
        allow(active_node.database_type_version).to receive(:default_port).and_return(3306)
      end

      it 'returns MySQL connection strings' do
        strings = active_credential.connection_strings

        expect(strings[:mysql]).to eq('mysql -h 192.168.1.100 -P 3306 -u testuser -ptestpass')
        expect(strings[:uri]).to eq('mysql://testuser:testpass@192.168.1.100:3306/')
        expect(strings[:jdbc]).to include('jdbc:mysql://')
        expect(strings[:rails]).to be_a(Hash)
        expect(strings[:rails][:adapter]).to eq('mysql2')
      end
    end

    context 'with MongoDB node' do
      before do
        allow(active_node).to receive(:database_type_slug).and_return('mongodb')
        allow(active_node.database_type_version).to receive(:default_port).and_return(27017)
      end

      it 'returns MongoDB connection strings' do
        strings = active_credential.connection_strings

        expect(strings[:mongo]).to include('mongosh')
        expect(strings[:uri]).to eq('mongodb://testuser:testpass@192.168.1.100:27017/admin')
        expect(strings[:connection_string]).to include('authSource=admin')
        expect(strings[:rails]).to be_a(Hash)
        expect(strings[:rails][:adapter]).to eq('mongoid')
      end
    end

    context 'with Cassandra node' do
      before do
        allow(active_node).to receive(:database_type_slug).and_return('cassandra')
        allow(active_node.database_type_version).to receive(:default_port).and_return(9042)
      end

      it 'returns Cassandra connection strings' do
        strings = active_credential.connection_strings

        expect(strings[:cqlsh]).to eq('cqlsh 192.168.1.100 9042 -u testuser -p testpass')
        expect(strings[:connection_string]).to include('contact_points=192.168.1.100')
        expect(strings[:driver]).to be_a(Hash)
        expect(strings[:driver][:contact_points]).to eq(['192.168.1.100'])
      end
    end

    context 'with unknown database type' do
      before do
        allow(active_node).to receive(:database_type_slug).and_return('unknown')
      end

      it 'returns empty hash' do
        expect(active_credential.connection_strings).to eq({})
      end
    end
  end
end
