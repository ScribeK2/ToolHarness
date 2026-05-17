class SearchController < ApplicationController
  # Reached by GET /q?q=<query>. The new workbench's mode controller focuses
  # the target input on "/"; this route is kept for backwards compatibility
  # with bookmarks and the legacy `search_path` helper. It redirects into
  # the workbench with the query pre-filled.
  def show
    target = params[:q].to_s.strip
    redirect_to workbench_path(target: target)
  end
end
