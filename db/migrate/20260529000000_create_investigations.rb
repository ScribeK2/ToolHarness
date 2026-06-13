class CreateInvestigations < ActiveRecord::Migration[8.1]
  def change
    create_table :investigations do |t|
      t.string  :domain,          null: false
      t.string  :track,           null: false, default: "orientation"
      t.string  :ticket_ref
      t.string  :status,          null: false, default: "pending"
      t.string  :verdict_status
      t.string  :suggested_track
      t.json    :findings,        null: false, default: []
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :investigations, :created_at
    add_index :investigations, :status

    add_reference :tool_runs, :investigation, null: true, foreign_key: true
    add_column :tool_runs, :step_order, :integer
  end
end
