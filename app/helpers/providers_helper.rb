# app/helpers/providers_helper.rb
module ProvidersHelper
  def form_builder_for_turbo(provider)
    form_with(model: provider) { |f| return f }
  end
end
