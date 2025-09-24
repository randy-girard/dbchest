module ProviderClient
  class Proxmox < ProviderClient::Base
    include ActionView::Helpers::NumberHelper

    # Register this client with the base class
    Base.register('proxmox', self)

    def exists?(node)
      proxmox_node = node.get_runtime_config_value("node")
      vmid = node.get_runtime_config_value("vmid")

      begin
        client.nodes[proxmox_node].lxc[vmid].status.current.get
        true
      rescue => ex
        false
      end
    end

    def nodes(args)
      client.nodes.get.map { |node|
        {
          "id" => node[:node],
          "name" => node[:node]
        }
      }
    end

    def storage(args)
      client.nodes[args[:node]]
            .storage
            .get
            .select { |storage| storage[:type] != "dir" }
            .map { |storage|
              avail = number_to_human_size(storage[:avail].to_i)
              total = number_to_human_size(storage[:total].to_i)
              {
                "id" => storage[:storage],
                "name" => "#{storage[:storage]} (#{avail} of #{total})"
              }
            }
    end

    def template_storage(args)
      client.nodes[args[:node]]
            .storage
            .get
            .select { |storage| storage[:type] == "dir" }
            .map { |storage|
              avail = number_to_human_size(storage[:avail].to_i)
              total = number_to_human_size(storage[:total].to_i)
              {
                "id" => storage[:storage],
                "name" => "#{storage[:storage]} (#{avail} of #{total})"
              }
            }
    end

    def template_template(args)
      client.nodes[args[:node]]
            .storage[args[:storage]]
            .content
            .get
            .select { |content| content[:content] == "vztmpl" }
            .map { |content|
              {
                "id" => content[:volid],
                "name" => content[:volid]
              }
            }
    end

    def ip(args)
      exec = client.nodes("pve").execute.post(commands: [])
      puts exec.inspect
      upid = exec["data"]["upid"]

      # Wait for the command to complete and retrieve the output
      loop do
        status = client.nodes(node).lxc(vmid).tasks(upid).status.get
        break if status["data"]["status"] == "stopped"
        sleep 1
      end

      # Fetch the command output
      output = client.nodes(node).lxc(vmid).tasks(upid).status.get["data"]["exitstatus_stdout"]
      puts "Command Output: #{output}"
    end

    private

    def client
      @client ||= begin
        api_url = URI.parse(settings.api_url)
        ProxmoxAPI.new(
          api_url.host,
          username: settings.username,
          password: settings.password,
          verify_ssl: false
        )
      end
    end
  end
end
