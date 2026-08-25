module Webhooks
  class StripeController < ApplicationController
    # Stripe posts here from its own servers — no browser, no CSRF token to check.
    skip_forgery_protection

    def create
      payload    = request.body.read
      sig_header = request.headers["Stripe-Signature"]
      secret     = ENV["STRIPE_WEBHOOK_SECRET"]

      # 1. Prove the event really came from Stripe. Without this, anyone who finds
      #    this URL could POST a fake "payment succeeded" and mint money.
      event = Stripe::Webhook.construct_event(payload, sig_header, secret)

      # 2. Inbox: record the event once. Stripe delivers at-least-once, so a
      #    redelivery we've already processed returns 200 immediately and touches
      #    no money. Non-money events are recorded too, for a full audit trail.
      inbox = StripeEvent.record(event, payload)
      return head :ok if inbox.processed?

      # 3. Money is real ONLY at payment_intent.succeeded — act only there. The
      #    processor's handlers are idempotent (keyed on the PI id), so even a
      #    retry after a mid-processing crash moves money exactly once. The same
      #    processor runs from the recovery sweep, so there is one money path.
      StripeEventProcessor.process(event)
      inbox.mark_processed!

      head :ok
    rescue Stripe::SignatureVerificationError, JSON::ParserError
      head :bad_request   # forged or malformed — refuse it, move no money
    rescue => e
      # Processing failed after the event was recorded. Mark it and return 500 so
      # Stripe redelivers; on that retry the inbox row is unprocessed, so we run
      # again, and the idempotent ledger keeps money exactly-once. Self-healing.
      # If Stripe gives up before then, ReprocessStuckStripeEventsJob sweeps it.
      inbox&.mark_failed!(e.message)
      Rails.logger.error("stripe webhook #{event&.id} (#{event&.type}) failed: #{e.message}")
      head :internal_server_error
    end
  end
end
