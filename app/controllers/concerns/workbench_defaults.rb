# Shared workbench defaults used by both the main workbench surface and the
# investigation surface (which renders inside the same layout/top bar).
module WorkbenchDefaults
  extend ActiveSupport::Concern

  # Tool keys pinned to the top-bar slots 1–5. Referenced as DEFAULT_SLOTS by
  # including controllers via the ancestor chain, and rendered by
  # app/views/workbench/_top_bar.html.erb through @default_slots.
  DEFAULT_SLOTS = %w[whois_lookup dns_lookup ssl_inspect email_auth_check http_inspect].freeze
end
