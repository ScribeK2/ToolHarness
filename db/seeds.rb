# Create default admin user if none exists
if defined?(User) && User.count.zero?
  email = ENV.fetch("TOOLHARNESS_DEFAULT_USER_EMAIL", "admin@localhost")
  password = ENV.fetch("TOOLHARNESS_DEFAULT_USER_PASSWORD", "changeme123")

  User.create!(
    email: email,
    password: password,
    password_confirmation: password
  )
  puts "Created default user: #{email}"
end
