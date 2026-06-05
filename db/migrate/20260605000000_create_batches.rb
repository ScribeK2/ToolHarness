class CreateBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :batches do |t|
      t.string :tool_key, null: false
      t.string :status, null: false, default: "running"
      t.integer :domain_count, null: false, default: 0
      t.datetime :completed_at
      t.timestamps
    end
    add_column :tool_runs, :batch_id, :integer
    add_index :tool_runs, :batch_id
  end
end
