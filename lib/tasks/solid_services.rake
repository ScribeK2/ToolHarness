namespace :db do
  desc "Load Solid Queue, Cache, and Cable schemas"
  task load_solid_schemas: :environment do
    puts "Loading Solid Queue schema..."
    load Rails.root.join("db/queue_schema.rb")

    puts "Loading Solid Cache schema..."
    load Rails.root.join("db/cache_schema.rb")

    puts "Loading Solid Cable schema..."
    load Rails.root.join("db/cable_schema.rb")

    puts "All Solid services schemas loaded!"
  end
end
