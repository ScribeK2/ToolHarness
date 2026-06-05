class BatchProgressJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(batch_id)
    batch = Batch.find(batch_id)
    batch.with_lock do
      if batch.status == "running" && batch.all_children_terminal?
        batch.update!(status: "completed", completed_at: Time.current)
      end
    end
    broadcast(batch)
  end

  private

  def broadcast(batch)
    Turbo::StreamsChannel.broadcast_replace_to(batch, target: "batch_table_#{batch.id}",
      partial: "batches/table", locals: { batch: batch })
    Turbo::StreamsChannel.broadcast_replace_to(batch, target: "batch_aggregate_#{batch.id}",
      partial: "batches/aggregate", locals: { batch: batch })
  rescue StandardError => e
    Rails.logger.error "BatchProgressJob broadcast failed for ##{batch.id}: #{e.class}: #{e.message}"
  end
end
