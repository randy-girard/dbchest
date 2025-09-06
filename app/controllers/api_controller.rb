class ApiController < ApplicationController

  def index
    @provider = Provider.find(params[:provider_id])
    @client = @provider.api_client
    @data = @client.call(params)

    Rails.logger.info @data.inspect

    render json: @data
  end

end
