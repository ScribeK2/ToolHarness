class Credentials::EntriesController < ApplicationController
  ID_RE = /\A[a-z0-9][a-z0-9_-]{0,39}\z/

  def create
    id   = params[:id].to_s.strip
    kind = params[:kind].to_s
    unless id.match?(ID_RE) && ToolHarness::CredentialStore::KINDS.include?(kind)
      return render_pane(error: "invalid id (use a-z 0-9 _ -) or kind")
    end

    store.save(
      id:     id,
      kind:   kind,
      secret: params[:secret].to_s,
      label:  params[:label].presence,
      host:   (params[:host] if kind == "host"),
      user:   (params[:user] if kind == "host")
    )
    render_pane
  end

  def destroy
    store.delete(params[:id])
    render_pane
  end

  private

  def store
    ToolHarness::CredentialStore.new
  end

  def render_pane(error: nil)
    render turbo_stream: turbo_stream.replace("credentials_pane",
             partial: "credentials/pane", locals: { error: error })
  end
end
