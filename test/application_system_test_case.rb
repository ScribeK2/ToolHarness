require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  # System tests drive the app through a real browser against the Capybara Puma
  # server thread, so background jobs must actually execute in-process — the
  # default :test adapter only enqueues them, leaving runs stuck "pending".
  # Run them inline, and restore the adapter afterward so nothing leaks.
  setup do
    @_prev_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
  end

  teardown do
    ActiveJob::Base.queue_adapter = @_prev_queue_adapter
  end
end
