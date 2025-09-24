module ProviderClient
  class Base
    attr_reader :settings

    def initialize(settings)
      @settings = settings
    end

    def call(params)
      function = params[:function]
      if function && respond_to?(function)
        send(function, params)
      end
    end
  end
end
