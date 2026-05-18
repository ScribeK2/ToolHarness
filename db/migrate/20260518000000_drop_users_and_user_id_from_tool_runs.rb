class DropUsersAndUserIdFromToolRuns < ActiveRecord::Migration[8.1]
  def up
    remove_index  :tool_runs, [:user_id, :created_at] if index_exists?(:tool_runs, [:user_id, :created_at])
    remove_reference :tool_runs, :user, foreign_key: true
    drop_table :users
  end

  def down
    create_table :users do |t|
      t.string   :email,              null: false, default: ""
      t.string   :encrypted_password, null: false, default: ""
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.timestamps null: false
    end
    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true

    add_reference :tool_runs, :user, foreign_key: true, null: false
    add_index :tool_runs, [:user_id, :created_at]
  end
end
