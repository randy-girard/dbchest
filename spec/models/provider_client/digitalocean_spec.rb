require 'rails_helper'
require 'ostruct'

RSpec.describe ProviderClient::DigitalOcean, type: :model do
  let(:settings) { OpenStruct.new(api_token: 'test_token') }
  let(:client) { described_class.new(settings) }
  let(:mock_http_client) { double('http_client') }

  describe '#initialize' do
    it 'sets up the client with settings' do
      expect(client.settings).to eq(settings)
    end

    it 'works with valid settings' do
      expect { described_class.new(settings) }.not_to raise_error
    end
  end

  describe '#exists?' do
    let(:node) { double('node', get_runtime_config_value: '123') }

    context 'when droplet exists' do
      before do
        mock_response = double('response', code: '200')
        allow(client).to receive(:api_request).with('GET', '/v2/droplets/123').and_return(mock_response)
      end

      it 'returns true' do
        expect(client.exists?(node)).to be true
      end
    end

    context 'when droplet does not exist' do
      let(:node_404) { double('node', get_runtime_config_value: '999') }

      before do
        mock_response = double('response', code: '404')
        allow(client).to receive(:api_request).with('GET', '/v2/droplets/999').and_return(mock_response)
      end

      it 'returns false' do
        expect(client.exists?(node_404)).to be false
      end
    end

    context 'when API returns error' do
      before do
        allow(client).to receive(:api_request).and_raise(StandardError, 'Network error')
      end

      it 'returns false' do
        expect(client.exists?(node)).to be false
      end
    end
  end

  describe '#nodes' do
    let(:regions_response_body) do
      {
        "regions" => [
          {
            "slug" => 'nyc1',
            "name" => 'New York 1',
            "available" => true
          },
          {
            "slug" => 'sfo2',
            "name" => 'San Francisco 2',
            "available" => true
          },
          {
            "slug" => 'lon1',
            "name" => 'London 1',
            "available" => false
          }
        ]
      }.to_json
    end

    before do
      mock_response = double('response', code: '200', body: regions_response_body)
      allow(client).to receive(:api_request).with('GET', '/v2/regions').and_return(mock_response)
    end

    it 'returns formatted droplet information' do
      nodes = client.nodes

      expect(nodes).to be_an(Array)
      expect(nodes.length).to eq(2)

      first_node = nodes.first
      expect(first_node["id"]).to eq('nyc1')
      expect(first_node["name"]).to eq('New York 1 (nyc1)')

      second_node = nodes.second
      expect(second_node["id"]).to eq('sfo2')
      expect(second_node["name"]).to eq('San Francisco 2 (sfo2)')
    end

    it 'handles API errors gracefully' do
      allow(client).to receive(:api_request).and_raise(StandardError, 'API error')
      expect(client.nodes).to eq([])
    end
  end

  describe '#storage' do
    it 'returns formatted volume information' do
      volumes = client.storage

      expect(volumes).to be_an(Array)
      expect(volumes.length).to eq(2)

      first_volume = volumes.first
      expect(first_volume["id"]).to eq('gp3')
      expect(first_volume["name"]).to eq('General Purpose SSD (gp3)')

      second_volume = volumes.second
      expect(second_volume["id"]).to eq('gp2')
      expect(second_volume["name"]).to eq('General Purpose SSD (gp2)')
    end
  end

  describe '#sizes' do
    let(:sizes_response_body) do
      {
        "sizes" => [
          {
            "slug" => 's-1vcpu-1gb',
            "memory" => 1024,
            "vcpus" => 1,
            "disk" => 25,
            "price_monthly" => 5.0,
            "available" => true,
            "regions" => [ 'nyc1', 'sfo2' ]
          },
          {
            "slug" => 's-2vcpu-2gb',
            "memory" => 2048,
            "vcpus" => 2,
            "disk" => 50,
            "price_monthly" => 10.0,
            "available" => true,
            "regions" => [ 'nyc1' ]
          }
        ]
      }.to_json
    end

    before do
      mock_response = double('response', code: '200', body: sizes_response_body)
      allow(client).to receive(:api_request).with('GET', '/v2/sizes').and_return(mock_response)
    end

    it 'returns formatted size information' do
      sizes = client.sizes

      expect(sizes).to be_an(Array)
      expect(sizes.length).to eq(2)

      first_size = sizes.first
      expect(first_size["id"]).to eq('s-1vcpu-1gb')
      expect(first_size["name"]).to eq('s-1vcpu-1gb - 1 vCPU, 1024MB RAM, 25GB SSD - $5.0/mo')

      second_size = sizes.second
      expect(second_size["id"]).to eq('s-2vcpu-2gb')
      expect(second_size["name"]).to eq('s-2vcpu-2gb - 2 vCPU, 2048MB RAM, 50GB SSD - $10.0/mo')
    end
  end

  describe '#images' do
    let(:images_response) do
      {
        images: [
          {
            id: 123456,
            slug: 'ubuntu-22-04-x64',
            name: 'Ubuntu 22.04 x64',
            distribution: 'Ubuntu',
            public: true,
            status: 'available',
            regions: [ 'nyc1', 'sfo2' ]
          },
          {
            id: 789012,
            slug: 'ubuntu-20-04-x64',
            name: 'Ubuntu 20.04 x64',
            distribution: 'Ubuntu',
            public: true,
            status: 'available',
            regions: [ 'nyc1' ]
          }
        ]
      }
    end

    before do
      images_response_body = {
        "images" => [
          {
            "id" => 123,
            "name" => 'Ubuntu 20.04 x64',
            "distribution" => 'Ubuntu',
            "slug" => 'ubuntu-20-04-x64',
            "public" => true,
            "status" => 'available',
            "regions" => [ 'nyc1', 'sfo2' ]
          },
          {
            "id" => 456,
            "name" => 'Ubuntu 22.04 x64',
            "distribution" => 'Ubuntu',
            "slug" => 'ubuntu-22-04-x64',
            "public" => true,
            "status" => 'available',
            "regions" => [ 'nyc1' ]
          }
        ]
      }.to_json

      mock_response = double('response', code: '200', body: images_response_body)
      allow(client).to receive(:api_request).with('GET', '/v2/images?type=distribution&per_page=100').and_return(mock_response)
    end

    it 'returns formatted image information' do
      images = client.images

      expect(images).to be_an(Array)
      expect(images.length).to eq(2)

      first_image = images.first
      expect(first_image["id"]).to eq('ubuntu-20-04-x64')
      expect(first_image["name"]).to eq('Ubuntu 20.04 x64 (Ubuntu)')

      second_image = images.second
      expect(second_image["id"]).to eq('ubuntu-22-04-x64')
      expect(second_image["name"]).to eq('Ubuntu 22.04 x64 (Ubuntu)')
    end
  end

  describe '#ssh_keys' do
    let(:ssh_keys_response) do
      {
        ssh_keys: [
          {
            id: 123,
            name: 'test-key-1',
            fingerprint: 'aa:bb:cc:dd:ee:ff:11:22:33:44:55:66:77:88:99:00',
            public_key: 'ssh-rsa AAAAB3...'
          },
          {
            id: 456,
            name: 'test-key-2',
            fingerprint: 'ff:ee:dd:cc:bb:aa:00:99:88:77:66:55:44:33:22:11',
            public_key: 'ssh-ed25519 AAAAC3...'
          }
        ]
      }
    end

    before do
      ssh_keys_response_body = {
        "ssh_keys" => [
          {
            "id" => 123,
            "name" => 'test-key-1',
            "fingerprint" => 'aa:bb:cc:dd:ee:ff:11:22:33:44:55:66:77:88:99:00',
            "public_key" => 'ssh-rsa AAAAB3...'
          },
          {
            "id" => 456,
            "name" => 'test-key-2',
            "fingerprint" => 'ff:ee:dd:cc:bb:aa:00:99:88:77:66:55:44:33:22:11',
            "public_key" => 'ssh-ed25519 AAAAC3...'
          }
        ]
      }.to_json

      mock_response = double('response', code: '200', body: ssh_keys_response_body)
      allow(client).to receive(:api_request).with('GET', '/v2/account/keys').and_return(mock_response)
    end

    it 'returns formatted SSH key information' do
      keys = client.ssh_keys

      expect(keys).to be_an(Array)
      expect(keys.length).to eq(2)

      first_key = keys.first
      expect(first_key["id"]).to eq('123')
      expect(first_key["name"]).to eq('test-key-1 (aa:bb:cc:dd:ee:ff...)')

      second_key = keys.second
      expect(second_key["id"]).to eq('456')
      expect(second_key["name"]).to eq('test-key-2 (ff:ee:dd:cc:bb:aa...)')
    end
  end

  describe '#vpcs' do
    before do
      vpcs_response_body = {
        "vpcs" => [
          {
            "id" => 'vpc-123',
            "name" => 'test-vpc-1',
            "ip_range" => '10.0.0.0/16',
            "region" => { "slug" => 'nyc1' },
            "default" => true
          },
          {
            "id" => 'vpc-456',
            "name" => 'test-vpc-2',
            "ip_range" => '172.16.0.0/16',
            "region" => { "slug" => 'nyc1' },
            "default" => false
          }
        ]
      }.to_json

      mock_response = double('response', code: '200', body: vpcs_response_body)
      allow(client).to receive(:api_request).with('GET', '/v2/vpcs?region=nyc1').and_return(mock_response)
    end

    it 'returns formatted VPC information' do
      vpcs = client.vpcs(region: 'nyc1')

      expect(vpcs).to be_an(Array)
      expect(vpcs.length).to eq(2)

      first_vpc = vpcs.first
      expect(first_vpc["id"]).to eq('vpc-123')
      expect(first_vpc["name"]).to eq('test-vpc-1 (10.0.0.0/16)')

      second_vpc = vpcs.second
      expect(second_vpc["id"]).to eq('vpc-456')
      expect(second_vpc["name"]).to eq('test-vpc-2 (172.16.0.0/16)')
    end
  end

  describe 'error handling' do
    it 'handles network timeouts gracefully' do
      allow(client).to receive(:api_request).and_raise(Timeout::Error, 'Request timeout')
      expect(client.nodes).to eq([])
    end

    it 'handles invalid JSON responses' do
      mock_response = double('response', code: '200', body: 'invalid json')
      allow(client).to receive(:api_request).with('GET', '/v2/regions').and_return(mock_response)
      expect(client.nodes).to eq([])
    end
  end

  describe 'class methods' do
    describe '.register' do
      it 'registers itself with the base class' do
        expect(ProviderClient::Base.registered_types).to include('digitalocean')
      end
    end
  end
end
