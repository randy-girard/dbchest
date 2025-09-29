require "net/http"
require "json"

module ProviderClient
  class DigitalOcean < ProviderClient::Base
    include ActionView::Helpers::NumberHelper

    # Register this client with the base class
    Base.register("digitalocean", self)

    def exists?(node)
      droplet_id = node.get_runtime_config_value("droplet_id")
      return false unless droplet_id

      begin
        response = api_request("GET", "/v2/droplets/#{droplet_id}")
        response.code == "200"
      rescue => ex
        Rails.logger.error "DigitalOcean API error checking droplet existence: #{ex.message}"
        false
      end
    end

    def nodes(args = {})
      begin
        response = api_request("GET", "/v2/regions")
        return [] unless response.code == "200"

        data = JSON.parse(response.body)
        data["regions"].select { |region| region["available"] }.map do |region|
          {
            "id" => region["slug"],
            "name" => "#{region["name"]} (#{region["slug"]})"
          }
        end
      rescue => ex
        Rails.logger.error "DigitalOcean API error fetching regions: #{ex.message}"
        []
      end
    end

    def storage(args = {})
      # DigitalOcean doesn't have separate storage selection like Proxmox
      # Return volume types instead
      [
        {
          "id" => "gp3",
          "name" => "General Purpose SSD (gp3)"
        },
        {
          "id" => "gp2",
          "name" => "General Purpose SSD (gp2)"
        }
      ]
    end

    def sizes(args = {})
      begin
        response = api_request("GET", "/v2/sizes")
        return [] unless response.code == "200"

        data = JSON.parse(response.body)
        data["sizes"].select { |size| size["available"] }.map do |size|
          {
            "id" => size["slug"],
            "name" => "#{size["slug"]} - #{size["vcpus"]} vCPU, #{size["memory"]}MB RAM, #{size["disk"]}GB SSD - $#{size["price_monthly"]}/mo"
          }
        end
      rescue => ex
        Rails.logger.error "DigitalOcean API error fetching sizes: #{ex.message}"
        []
      end
    end

    def images(args = {})
      begin
        # Get Ubuntu images
        response = api_request("GET", "/v2/images?type=distribution&per_page=100")
        return [] unless response.code == "200"

        data = JSON.parse(response.body)
        ubuntu_images = data["images"].select do |image|
          image["distribution"] == "Ubuntu" &&
          image["status"] == "available" &&
          image["public"] == true
        end

        ubuntu_images.map do |image|
          {
            "id" => image["slug"] || image["id"].to_s,
            "name" => "#{image["name"]} (#{image["distribution"]})"
          }
        end
      rescue => ex
        Rails.logger.error "DigitalOcean API error fetching images: #{ex.message}"
        []
      end
    end

    def ssh_keys(args = {})
      begin
        response = api_request("GET", "/v2/account/keys")
        return [] unless response.code == "200"

        data = JSON.parse(response.body)
        data["ssh_keys"].map do |key|
          {
            "id" => key["id"].to_s,
            "name" => "#{key["name"]} (#{key["fingerprint"][0..16]}...)"
          }
        end
      rescue => ex
        Rails.logger.error "DigitalOcean API error fetching SSH keys: #{ex.message}"
        []
      end
    end

    def vpcs(args = {})
      region = args[:region]
      return [] unless region

      begin
        response = api_request("GET", "/v2/vpcs?region=#{region}")
        return [] unless response.code == "200"

        data = JSON.parse(response.body)
        vpcs = data["vpcs"].select { |vpc| vpc["region"]["slug"] == region }

        vpcs.map do |vpc|
          {
            "id" => vpc["id"],
            "name" => "#{vpc["name"]} (#{vpc["ip_range"]})"
          }
        end
      rescue => ex
        Rails.logger.error "DigitalOcean API error fetching VPCs: #{ex.message}"
        []
      end
    end

    def create_droplet(params)
      droplet_config = {
        name: params[:name],
        region: params[:region],
        size: params[:size],
        image: params[:image],
        ssh_keys: params[:ssh_keys] || [],
        vpc_uuid: params[:vpc_uuid],
        user_data: params[:user_data],
        monitoring: true,
        tags: [ "dbchest", "database", params[:database_type] ].compact
      }

      begin
        response = api_request("POST", "/v2/droplets", droplet_config.to_json)

        if response.code == "202"
          data = JSON.parse(response.body)
          {
            success: true,
            droplet_id: data["droplet"]["id"],
            droplet: data["droplet"]
          }
        else
          {
            success: false,
            error: "Failed to create droplet: #{response.body}"
          }
        end
      rescue => ex
        Rails.logger.error "DigitalOcean API error creating droplet: #{ex.message}"
        {
          success: false,
          error: ex.message
        }
      end
    end

    def destroy_droplet(droplet_id)
      begin
        response = api_request("DELETE", "/v2/droplets/#{droplet_id}")

        {
          success: response.code == "204",
          message: response.code == "204" ? "Droplet destroyed successfully" : "Failed to destroy droplet"
        }
      rescue => ex
        Rails.logger.error "DigitalOcean API error destroying droplet: #{ex.message}"
        {
          success: false,
          error: ex.message
        }
      end
    end

    def get_droplet_info(droplet_id)
      begin
        response = api_request("GET", "/v2/droplets/#{droplet_id}")

        if response.code == "200"
          data = JSON.parse(response.body)
          data["droplet"]
        else
          nil
        end
      rescue => ex
        Rails.logger.error "DigitalOcean API error getting droplet info: #{ex.message}"
        nil
      end
    end

    private

    def api_request(method, endpoint, body = nil)
      uri = URI("https://api.digitalocean.com#{endpoint}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      case method.upcase
      when "GET"
        request = Net::HTTP::Get.new(uri)
      when "POST"
        request = Net::HTTP::Post.new(uri)
        request.body = body if body
        request["Content-Type"] = "application/json"
      when "DELETE"
        request = Net::HTTP::Delete.new(uri)
      else
        raise ArgumentError, "Unsupported HTTP method: #{method}"
      end

      request["Authorization"] = "Bearer #{settings.api_token}"
      request["User-Agent"] = "DBChest/1.0"

      http.request(request)
    end
  end
end
