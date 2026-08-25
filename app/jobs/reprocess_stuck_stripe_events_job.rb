# Recovery sweep. Stripe retries a failed webhook for ~3 days, then gives up. An
# event stuck 'received' (we recorded it, then crashed before processing) or
# 'failed' (a handler raised) would then never be booked — money owed, surfaced
# by reconciliation as "missing" with no way to remediate it.
#
# This re-runs every non-processed inbox event through the SAME idempotent
# processor the webhook uses. The ledger is keyed on the PI id, so replaying an
# event that already posted is a no-op. Safe to run on a schedule or by hand
# (`rails stripe:reprocess`).
class ReprocessStuckStripeEventsJob < ApplicationJob
  queue_as :default

  def perform
    reprocessed = 0
    StripeEvent.where(status: %w[received failed]).find_each do |event|
      StripeEventProcessor.process_payload(event.payload)
      event.mark_processed!
      reprocessed += 1
    rescue => e
      event.mark_failed!(e.message)
      Rails.logger.error("reprocess #{event.event_id} (#{event.event_type}) failed: #{e.message}")
    end
    Rails.logger.info("[reprocess] swept #{reprocessed} stuck event(s) back to processed")
    reprocessed
  end
end
