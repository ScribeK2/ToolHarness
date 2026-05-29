class AddSkipReasonToToolRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :tool_runs, :skip_reason, :string
  end
end
