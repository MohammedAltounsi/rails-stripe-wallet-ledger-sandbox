# Turns a verified Stripe event into ledger movement. Extracted from the webhook
# controller so the recovery sweep (ReprocessStuckStripeEventsJob) can replay a
# stored event through the EXACT same idempotent handlers — no second copy of the
# money logic that could drift from the live path.
module StripeEventProcessor
  # Money is real only at payment_intent.succeeded. The handlers are keyed on the
  # PI id, so processing an event that already posted moves money zero more times.
  def self.process(event)
    handle_succeeded(event.data.object) if event.type == "payment_intent.succeeded"
  end

  # Rebuild an event from the raw payload the inbox stored, then process it. This
  # is how the recovery sweep reprocesses an event Stripe already delivered once.
  def self.process_payload(payload)
    process(Stripe::Event.construct_from(JSON.parse(payload)))
  end

  # One PaymentIntent can mean two things. The metadata.purpose tells us which.
  def self.handle_succeeded(pi)
    case pi.metadata["purpose"]
    when "wallet_topup" then credit_wallet(pi)
    when "coffee_order" then settle_order(pi)
    end
  end

  # Top-up: pull cash in, credit the customer's wallet. Keyed on the PI id so a
  # redelivered webhook (Stripe delivers at-least-once) credits exactly once.
  def self.credit_wallet(pi)
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
  def self.settle_order(pi)
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
  # and the caller must still succeed so Stripe doesn't keep retrying.
  def self.send_receipt(order)
    return if order.email.blank?
    OrderMailer.receipt(order).deliver_later
  rescue => e
    Rails.logger.error("receipt email failed for #{order.reference}: #{e.message}")
  end
end
