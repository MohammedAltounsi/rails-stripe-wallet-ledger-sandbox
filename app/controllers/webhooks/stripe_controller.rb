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
      #    handlers are themselves idempotent (keyed on the PI id), so even a retry
      #    after a mid-processing crash moves money exactly once.
      handle_succeeded(event.data.object) if event.type == "payment_intent.succeeded"
      inbox.mark_processed!

      head :ok
    rescue Stripe::SignatureVerificationError, JSON::ParserError
      head :bad_request   # forged or malformed — refuse it, move no money
    rescue => e
      # Processing failed after the event was recorded. Mark it and return 500 so
      # Stripe redelivers; on that retry the inbox row is unprocessed, so we run
      # again, and the idempotent ledger keeps money exactly-once. Self-healing.
      inbox&.mark_failed!(e.message)
      Rails.logger.error("stripe webhook #{event&.id} (#{event&.type}) failed: #{e.message}")
      head :internal_server_error
    end

    private

    # One PaymentIntent can mean two things. The metadata.purpose tells us which.
    def handle_succeeded(pi)
      case pi.metadata["purpose"]
      when "wallet_topup" then credit_wallet(pi)
      when "coffee_order" then settle_order(pi)
      end
    end

    # Top-up: pull cash in, credit the customer's wallet. Keyed on the PI id so a
    # redelivered webhook (Stripe delivers at-least-once) credits exactly once.
    def credit_wallet(pi)
      ref = pi.metadata["customer_ref"] || "unknown"
      Ledger.post!(
        "stripe topup #{pi.id}",
        [[Ledger.account(Ledger::CASH_ACCOUNT), -pi.amount],
         [Ledger.account("wallet:#{ref}"), pi.amount]],
        key: "stripe-pi:#{pi.id}"
      )
    end

    # Direct card order: pull cash in, book it as revenue, mark the order paid.
    # Both the ledger post and the status flip are safe to replay on redelivery.
    def settle_order(pi)
      order = Order.find_by(id: pi.metadata["order_id"])
      return unless order
      return if order.paid?   # redelivery of an already-settled order: don't re-post or re-email

      # The server sets the PI amount from the order, so these match on the happy
      # path. If they ever diverge, refuse to auto-settle: book nothing and leave
      # the order pending for manual review. The charge exists in Stripe but not in
      # the ledger, so reconciliation reports it in its "missing" bucket. (Booking
      # it anyway would silently record the wrong revenue with no way to surface it.)
      if pi.amount != order.total_cents
        Rails.logger.error("settle_order amount mismatch: pi #{pi.id} charged #{pi.amount}, order #{order.reference} total #{order.total_cents} — leaving pending for review")
        return
      end

      Ledger.post!(
        "card order #{order.reference}",
        [[Ledger.account(Ledger::CASH_ACCOUNT), -pi.amount],
         [Ledger.account(Ledger::REVENUE_ACCOUNT), pi.amount]],
        key: "stripe-pi:#{pi.id}"
      )
      order.update!(status: "paid", stripe_payment_intent_id: pi.id)
      send_receipt(order)
    end

    # Email the receipt, swallowing any failure — the payment is already recorded
    # and the webhook must still return 200 so Stripe doesn't keep retrying.
    def send_receipt(order)
      return if order.email.blank?
      OrderMailer.receipt(order).deliver_later
    rescue => e
      Rails.logger.error("receipt email failed for #{order.reference}: #{e.message}")
    end
  end
end
