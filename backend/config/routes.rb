Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  namespace :api do
    get "health", to: "auth#health"
    post "webhooks/deploy", to: "webhooks#deploy"
    post "services/:id/webhooks/:token/deploy", to: "webhooks#service_deploy", as: :service_webhook_deploy
    post "login", to: "auth#login"
    get "me", to: "auth#me"
    get "setup", to: "users#setup_required"
    post "users", to: "users#create"

    resources :projects do
      resource :manifest, only: [ :show, :update ] do
        post :preview, on: :collection
        post :apply, on: :collection
        get :status, on: :collection
      end
      resources :services, shallow: true do
        member do
          post :deploy
          post :rollback
          post :scale
          get :logs
          get :metrics
          get :container_status
          get :database_info
          get :backups
          get :backup_schedules
          post :create_backup_schedule
          post :link
          post :unlink
          get :linked_by
          post :backup
          post :restore
          post :start
          post :stop
          post :restart
          post :rebuild
          post :run
          post :enter
          post :app_lock
          post :app_unlock
          get :app_locked
          post :generate_domain
        end
        collection do
          get :config_show
          get :traefik_config
          get :storage_list
        end
        resources :deployments, only: [ :index, :show ]
        resources :environment_variables, path: "env-vars", only: [ :create ]
        resources :domains, only: [ :create ]
        resources :storage_mounts, path: "storage", only: [ :create ]
      end
      resources :activity_events, path: "activity-events", only: [ :index ]
      get :activity, on: :member
      patch :shared_vars, on: :member
      post :deploy_all, on: :member
      post :restart_all, on: :member
      post :stop_all, on: :member
    end

    # Service sub-resource destroy actions (not shallow — stay under /services/:id/...)
    scope "/services/:service_id" do
      delete "env-vars/:key", to: "environment_variables#destroy"
      delete "domains/:hostname", to: "domains#destroy", constraints: { hostname: /[^\/]+/ }
      delete "storage/*host_path", to: "storage_mounts#destroy", format: false
      delete "backup_schedules/:schedule_id", to: "services#destroy_backup_schedule"
    end

    resources :servers do
      member do
        post :validate
        get :metrics
      end
    end

    resources :organizations do
      resources :projects, only: [ :index, :create ]
      resources :git_sources, path: "git-sources", only: [ :index, :create, :destroy ] do
        member do
          get :repos
        end
      end
      resources :members, controller: "organization_members", only: [ :index, :create, :destroy, :update ]
      resources :deploy_keys, path: "deploy-keys", only: [ :index, :create, :destroy ]
    end

    resources :git_sources, path: "git-sources" do
      member do
        get :repos
      end
    end
    resources :deploy_keys, path: "deploy-keys", only: [ :index, :create, :destroy ]
    resources :templates, only: [ :index ] do
      member do
        post :deploy
      end
    end
    get "activity", to: "activity_events#global"

    resources :builders, only: [ :index ]
    resources :networks, only: [ :index ]

    get "config", to: "config#index"

    namespace :admin do
      get "settings", to: "settings#index"
      patch "settings", to: "settings#update"
      post "settings/test-github-app", to: "settings#test_github_app"

      get "github-app-manifest", to: "github_app_manifests#manifest"
      get "github-app-manifest/callback", to: "github_app_manifests#callback"
      get "github-app-manifest/setup", to: "github_app_manifests#setup"
      delete "github-app", to: "github_app_manifests#destroy_app"
    end

    get "github-apps/callback", to: "github_apps#callback"
    post "github-apps/finish-setup", to: "github_apps#finish_setup"
    delete "github-apps/installations/:id", to: "github_apps#destroy_installation"
    post "github-apps/webhook", to: "github_apps#webhook"
  end
end
