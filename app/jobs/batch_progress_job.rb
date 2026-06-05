class BatchProgressJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  # Fleshed out in the bulk-ops feature; stub keeps the parent-notify hook wired.
  def perform(batch_id); end
end
