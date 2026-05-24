class Sql::RecipesController < ApplicationController
  NAME_RE = /\A[a-z0-9][a-z0-9-]{0,39}\z/.freeze

  def index
    render turbo_stream: turbo_stream.replace("sql_recipe_palette",
             partial: "workbench/sql/recipe_palette",
             locals:  { recipes: store.all, active: 0, error: nil })
  end

  def create
    name = params[:name].to_s
    sql  = params[:sql].to_s
    confirm = params[:confirm].to_s == "true"

    unless name.match?(NAME_RE)
      return render_palette_error("invalid name (a-z 0-9 - only, 1-40 chars)", status: :unprocessable_entity)
    end
    if sql.strip.empty?
      return render_palette_error(":save-recipe needs SQL in the editor", status: :unprocessable_entity)
    end
    if store.exists?(name: name) && !confirm
      return render_palette_error("recipe '#{name}' exists — overwrite? confirm=true", status: :conflict)
    end

    store.save(name: name, sql: sql)
    render turbo_stream: [
      turbo_stream.replace("sql_recipe_palette",
        partial: "workbench/sql/recipe_palette",
        locals:  { recipes: store.all, active: 0, error: nil }),
      turbo_stream.replace("sql_workbench_status",
        partial: "workbench/sql/status_flash",
        locals:  { message: "recipe '#{name}' saved" })
    ]
  end

  def destroy
    name = params[:name].to_s
    if store.delete(name: name)
      render turbo_stream: turbo_stream.replace("sql_recipe_palette",
               partial: "workbench/sql/recipe_palette",
               locals:  { recipes: store.all, active: 0, error: nil })
    else
      render_palette_error("cannot delete '#{name}' (starters are not deletable)", status: :unprocessable_entity)
    end
  end

  private

  def store
    @store ||= ToolHarness::Sql::RecipeStore.new
  end

  def render_palette_error(message, status:)
    render status: status, turbo_stream: turbo_stream.replace("sql_recipe_palette",
             partial: "workbench/sql/recipe_palette",
             locals:  { recipes: store.all, active: 0, error: message })
  end
end
