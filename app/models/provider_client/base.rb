module ProviderClient
  class Base
    attr_reader :settings

    # Registry for provider client implementations
    @clients = {}

    def self.register(provider_type, client_class)
      @clients[provider_type.to_s] = client_class
    end

    def self.for_provider(provider)
      client_class = @clients[provider.provider_type.key]
      if client_class
        client_class.new(provider.provider_settings_object)
      else
        raise ArgumentError, "Unknown provider type: #{provider.provider_type.key}. Available types: #{@clients.keys.join(', ')}"
      end
    end

    def self.registered_types
      @clients.keys
    end

    def initialize(settings)
      @settings = settings
    end

    def call(params)
      function = params[:function]
      if function && respond_to?(function)
        send(function, params)
      end
    end

    # Abstract methods that should be implemented by subclasses
    def exists?(node)
      raise NotImplementedError, "#{self.class} must implement #exists?"
    end

    def nodes(args = {})
      raise NotImplementedError, "#{self.class} must implement #nodes"
    end

    def storage(args = {})
      raise NotImplementedError, "#{self.class} must implement #storage"
    end
  end
end
