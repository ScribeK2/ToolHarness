class DropDomainChecksAndFeedbacks < ActiveRecord::Migration[8.1]
  # Drops the SiteProbe-legacy tables. Their controllers, models, views, jobs,
  # mailer, and channel have all been removed; tool_runs replaces them.
  def up
    drop_table :feedbacks if table_exists?(:feedbacks)
    drop_table :domain_checks if table_exists?(:domain_checks)
  end

  def down
    create_table :domain_checks do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :domain, null: false
      t.string  :status, default: "pending", null: false
      t.boolean :scan_subdomains, default: false
      t.json    :whois_data
      t.json    :dns_data
      t.json    :ssl_data
      t.json    :http_data
      t.json    :email_data
      t.json    :subdomain_data
      t.timestamps
      t.index :domain
    end

    create_table :feedbacks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :domain_check, null: false, foreign_key: true
      t.integer :accuracy_rating
      t.text    :comments
      t.timestamps
    end
  end
end
