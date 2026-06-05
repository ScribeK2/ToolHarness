Rails.application.routes.draw do
  # Workbench — the front door
  get "workbench", to: "workbench#show", as: :workbench
  root to: "workbench#show"

  # Search retained for the / shortcut auto-detect (used by mode controller)
  get "q", to: "search#show", as: :search

  # Tool execution — POST endpoint still in use by the target row form
  post "tools/:tool_key/run", to: "tool_runs#create", as: :tool_run_create

  # Re-run a prior run by replaying its stored input
  post "runs/:id/rerun", to: "tool_runs#rerun", as: :tool_run_rerun

  # Investigations — domain-anchored orchestration over real ToolRuns
  resources :investigations, only: %i[create show]

  # Commands API
  post "commands", to: "commands#create", as: :commands

  # Action Cable
  mount ActionCable.server => "/cable"

  # Health
  get "up" => "rails/health#show", as: :rails_health_check

  # Credentials management
  namespace :credentials do
    resources :entries, only: %i[create destroy]
  end

  # SQL Workbench
  namespace :sql, path: "workbench/sql" do
    resources :profiles, only: %i[new create update destroy], param: :name
    resource  :session,  only: %i[create destroy update]
    resources :queries,  only: %i[create]
    resources :history,  only: %i[index]
    resources :recipes,  only: %i[index create destroy], param: :name
    resources :cells,    only: %i[show], param: :id
  end
end
