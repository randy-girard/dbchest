require "sidekiq/web"

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"

  get "/api/providers/:provider_id" => "api#index", as: :api

  resources :providers do
    get :config_partial, on: :collection
  end

  resources :clusters do
    resources :nodes do
      get :config_partial, on: :collection
      member do
        get :add_replica
        post :create_replica
        get :confirm_destroy
      end
      resources :credentials
    end
    # Status API for ActionCable fallback
    get "nodes/status", to: "nodes_status#index"

    # Cluster dashboard
    resource :dashboard, controller: 'cluster_dashboards', only: [:show] do
      get :metrics_summary
      get :live_status
    end
  end

  # Individual node status API
  get "nodes/:id/status", to: "nodes_status#show", as: :node_status

  # Cloud-init callback API
  post "nodes/:id/status_callback", to: "node_status_callbacks#update", as: :node_status_callback

  # Node metrics API
  resources :nodes, only: [] do
    resources :metrics, controller: 'node_metrics', only: [:create, :index] do
      collection do
        get :latest
        get :summary
      end
    end

    # Node dashboard
    resource :dashboard, controller: 'node_dashboards', only: [:show] do
      get :metrics_data
      get :live_metrics
    end
  end

  # ActionCable test routes (development/testing)
  get "action_cable_test", to: "action_cable_test#index"
  post "action_cable_test/:id/broadcast", to: "action_cable_test#broadcast_test"

  # Web-based ActionCable testing (works with async adapter)
  get "test_actioncable/:node_id", to: "test_action_cable#show", as: :test_actioncable_node
  post "test_actioncable/:node_id/update_status", to: "test_action_cable#update_status", as: :test_actioncable_update

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ActionCable routes
  mount ActionCable.server => "/cable"

  # Defines the root path route ("/")
  root "dashboard#index"
end
