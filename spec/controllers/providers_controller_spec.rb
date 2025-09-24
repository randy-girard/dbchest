require 'rails_helper'

RSpec.describe ProvidersController, type: :controller do
  let(:provider_type) { create(:provider_type) }
  let(:provider) { create(:provider, provider_type: provider_type) }
  let(:valid_attributes) { { name: "Test Provider", provider_type_id: provider_type.id } }
  let(:invalid_attributes) { { name: "", provider_type_id: nil } }

  describe "GET #index" do
    it "returns a success response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns @providers" do
      provider # create the provider
      get :index
      expect(assigns(:providers)).to include(provider)
    end

    context "with multiple providers" do
      let!(:providers) { create_list(:provider, 3, provider_type: provider_type) }

      it "assigns all providers" do
        get :index
        expect(assigns(:providers)).to match_array(providers)
      end
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      get :show, params: { id: provider.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested provider" do
      get :show, params: { id: provider.to_param }
      expect(assigns(:provider)).to eq(provider)
    end

    context "with non-existent provider" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "GET #new" do
    it "returns a success response" do
      get :new
      expect(response).to be_successful
    end

    it "assigns a new provider" do
      get :new
      expect(assigns(:provider)).to be_a_new(Provider)
    end

    it "assigns provider types" do
      get :new
      expect(assigns(:provider_types)).to include(provider_type)
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      get :edit, params: { id: provider.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested provider" do
      get :edit, params: { id: provider.to_param }
      expect(assigns(:provider)).to eq(provider)
    end

    it "assigns provider types" do
      get :edit, params: { id: provider.to_param }
      expect(assigns(:provider_types)).to include(provider_type)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Provider" do
        expect {
          post :create, params: { provider: valid_attributes }
        }.to change(Provider, :count).by(1)
      end

      it "redirects to the created provider" do
        post :create, params: { provider: valid_attributes }
        expect(response).to redirect_to(Provider.last)
      end

      it "assigns the provider" do
        post :create, params: { provider: valid_attributes }
        expect(assigns(:provider)).to be_persisted
      end

      it "sets a success notice" do
        post :create, params: { provider: valid_attributes }
        expect(flash[:notice]).to eq("Provider was successfully created.")
      end
    end

    context "with invalid params" do
      it "does not create a new Provider" do
        expect {
          post :create, params: { provider: invalid_attributes }
        }.not_to change(Provider, :count)
      end

      it "renders the new template" do
        post :create, params: { provider: invalid_attributes }
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "assigns provider types" do
        post :create, params: { provider: invalid_attributes }
        expect(assigns(:provider_types)).to include(provider_type)
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) { { name: "Updated Provider" } }

      it "updates the requested provider" do
        put :update, params: { id: provider.to_param, provider: new_attributes }
        provider.reload
        expect(provider.name).to eq("Updated Provider")
      end

      it "redirects to the provider" do
        put :update, params: { id: provider.to_param, provider: new_attributes }
        expect(response).to redirect_to(provider)
      end

      it "assigns the provider" do
        put :update, params: { id: provider.to_param, provider: new_attributes }
        expect(assigns(:provider)).to eq(provider)
      end

      it "sets a success notice" do
        put :update, params: { id: provider.to_param, provider: new_attributes }
        expect(flash[:notice]).to eq("Provider was successfully updated.")
      end
    end

    context "with invalid params" do
      it "does not update the provider" do
        original_name = provider.name
        put :update, params: { id: provider.to_param, provider: invalid_attributes }
        provider.reload
        expect(provider.name).to eq(original_name)
      end

      it "renders the edit template" do
        put :update, params: { id: provider.to_param, provider: invalid_attributes }
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "assigns provider types" do
        put :update, params: { id: provider.to_param, provider: invalid_attributes }
        expect(assigns(:provider_types)).to include(provider_type)
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested provider" do
      provider # create the provider
      expect {
        delete :destroy, params: { id: provider.to_param }
      }.to change(Provider, :count).by(-1)
    end

    it "redirects to the providers list" do
      delete :destroy, params: { id: provider.to_param }
      expect(response).to redirect_to(providers_url)
    end

    it "sets a success notice" do
      delete :destroy, params: { id: provider.to_param }
      expect(flash[:notice]).to eq("Provider was successfully destroyed.")
    end
  end

  describe "GET #config_partial" do
    it "returns a success response" do
      get :config_partial, params: { type: provider_type.id }
      expect(response).to be_successful
    end

    it "assigns the provider type" do
      get :config_partial, params: { type: provider_type.id }
      expect(assigns(:provider_type)).to eq(provider_type)
    end

    it "assigns a new provider with the provider type" do
      get :config_partial, params: { type: provider_type.id }
      expect(assigns(:provider)).to be_a_new(Provider)
      expect(assigns(:provider).provider_type).to eq(provider_type)
    end

    it "builds provider settings" do
      option = create(:provider_type_option, provider_type: provider_type)
      get :config_partial, params: { type: provider_type.id }
      expect(assigns(:provider).provider_settings).not_to be_empty
    end

    it "renders the config_partial template" do
      get :config_partial, params: { type: provider_type.id }
      expect(response).to render_template("providers/config_partial")
    end
  end

  # JSON format tests
  describe "JSON responses" do
    describe "POST #create" do
      context "with valid params" do
        it "returns JSON with created status" do
          post :create, params: { provider: valid_attributes }, format: :json
          expect(response).to have_http_status(:created)
          expect(response.content_type).to include('application/json')
        end
      end

      context "with invalid params" do
        it "returns JSON with errors" do
          post :create, params: { provider: invalid_attributes }, format: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.content_type).to include('application/json')
        end
      end
    end

    describe "PUT #update" do
      context "with valid params" do
        it "returns JSON with ok status" do
          put :update, params: { id: provider.to_param, provider: { name: "Updated" } }, format: :json
          expect(response).to have_http_status(:ok)
          expect(response.content_type).to include('application/json')
        end
      end

      context "with invalid params" do
        it "returns JSON with errors" do
          put :update, params: { id: provider.to_param, provider: invalid_attributes }, format: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.content_type).to include('application/json')
        end
      end
    end

    describe "DELETE #destroy" do
      it "returns no content status" do
        delete :destroy, params: { id: provider.to_param }, format: :json
        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
