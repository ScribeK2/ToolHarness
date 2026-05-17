class CreateToolRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_runs do |t|
      t.references :user, null: false, foreign_key: true

      t.string  :tool_key,      null: false
      t.string  :tool_name,     null: false
      t.string  :category,      null: false
      t.string  :input_type

      t.json    :input,         null: false, default: {}
      t.string  :input_summary

      t.string  :status,        null: false, default: "pending"
      t.boolean :success,       null: false, default: false
      t.boolean :cached,        null: false, default: false

      t.json    :result_data,   default: {}
      t.json    :issues,        default: []
      t.json    :recommendations, default: []
      t.string  :summary
      t.text    :error

      t.float    :execution_time
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :checked_at

      t.timestamps
    end

    add_index :tool_runs, :tool_key
    add_index :tool_runs, :category
    add_index :tool_runs, :success
    add_index :tool_runs, :input_summary
    add_index :tool_runs, [:user_id, :created_at]
    add_index :tool_runs, [:tool_key, :created_at]
  end
end
