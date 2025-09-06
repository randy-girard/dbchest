module ProviderClient
  class Base
    attr_reader :settings
    
    def initialize(settings)
      @settings = settings
    end

    def call(params)
      if respond_to?(params[:function])
        send(params[:function], params)
      end
    end
  end
end
