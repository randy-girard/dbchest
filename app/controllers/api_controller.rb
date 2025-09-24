class ApiController < ApplicationController
  def index
    @provider = Provider.find(params[:provider_id])
    @client = @provider.api_client

    if @client.nil?
      Rails.logger.error "No API client available for provider #{@provider.id} (type: #{@provider.provider_type.key})"
      render json: { error: "Provider client not available for #{@provider.provider_type.key}" }, status: :unprocessable_content
      return
    end

    @data = @client.call(params)

    Rails.logger.info @data.inspect

    render json: @data
  rescue => e
    Rails.logger.error "API call failed: #{e.message}"
    render json: { error: "API call failed: #{e.message}" }, status: :internal_server_error
  end
end
