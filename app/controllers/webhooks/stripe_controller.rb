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

      # 2. Money is real ONLY at payment_intent.succeeded — act only there.
      handle_succeeded(event.data.object) if event.type == "payment_intent.succeeded"

      head :ok
    rescue Stripe::SignatureVerificationError, JSON::ParserError
      head :bad_request   # forged or malformed — refuse it, move no money
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

      # Defense-in-depth: the server sets the PI amount from the order, so these
      # always match. Log loudly if they ever diverge — reconciliation catches it too.
      if pi.amount != order.total_cents
        Rails.logger.error("settle_order amount mismatch: pi #{pi.id} charged #{pi.amount}, order #{order.reference} total #{order.total_cents}")
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
