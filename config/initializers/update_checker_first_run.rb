# Production-only kick of UpdateChecker.refresh! on Rails boot when the cache
# is empty. The Solid Queue recurring job (config/recurring.yml) handles every
# subsequent refresh at 24h. Without this, the banner cannot appear until the
# first scheduled run, which is 24h after first launch — leaving brand-new
# AppImage users with no update visibility on day one.

Rails.application.config.after_initialize do
  next unless Rails.env.production?

  Thread.new do
    sleep 2
    next if Rails.cache.read(UpdateChecker::CACHE_KEY)
    UpdateChecker.refresh!
  rescue StandardError => e
    Rails.logger.info("UpdateChecker first-run thread failed: #{e.class}: #{e.message}")
  end
end
