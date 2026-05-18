class UpdateCheckJob < ApplicationJob
  queue_as :default

  def perform
    UpdateChecker.refresh!
  end
end
