Rails.application.routes.draw do
  # Internal-only authentication (no registration)
  devise_for :users, skip: [:registrations]

  # Dashboard
  get "dashboard", to: "dashboard#index"
  get "workbench", to: "workbench#show", as: :workbench
  root to: "dashboard#index"

  # Global quick-search — auto-detects domain / IP / email / ticket.
  get "q", to: "search#show", as: :search

  # ToolHarness — catalog, per-tool form, run lifecycle
  get  "tools",               to: "tools#index",       as: :tools
  get  "tools/:tool_key",     to: "tools#show",        as: :tool
  post "tools/:tool_key/run", to: "tool_runs#create",  as: :tool_run_create
  resources :tool_runs, only: [:index, :show]

  # Cmdline dispatcher — server-side handler for :run / :export commands.
  post "commands", to: "commands#create", as: :commands

  # Action Cable WebSocket mount — required for Turbo Streams real-time broadcasts.
  mount ActionCable.server => "/cable"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
