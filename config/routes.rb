Rails.application.routes.draw do
  # Workbench — the front door
  get "workbench", to: "workbench#show", as: :workbench
  root to: "workbench#show"

  # Search retained for the / shortcut auto-detect (used by mode controller)
  get "q", to: "search#show", as: :search

  # Tool execution — POST endpoint still in use by the target row form
  post "tools/:tool_key/run", to: "tool_runs#create", as: :tool_run_create

  # Commands API
  post "commands", to: "commands#create", as: :commands

  # Action Cable
  mount ActionCable.server => "/cable"

  # Health
  get "up" => "rails/health#show", as: :rails_health_check

  # SQL Workbench
  namespace :sql, path: "workbench/sql" do
    resources :profiles, only: %i[create update destroy], param: :name
    resource  :session,  only: %i[create destroy update]
    resources :queries,  only: %i[create]
    resources :history,  only: %i[index]
    resources :cells,    only: %i[show], param: :id
  end
end
