module StripeGateway
  # Ask Stripe to set up a card charge for a wallet top-up (test mode = fake money).
  #
  # IMPORTANT: this does NOT credit the wallet. Creating a PaymentIntent only says
  # "I intend to take this money." The card might fail, 3-D Secure might be declined,
  # the customer might close the tab. The wallet is credited later and ONLY when
  # Stripe tells us the money actually cleared — via the webhook. Never trust the
  # create call; trust the webhook.
  def self.create_topup_intent(customer_ref:, amount_cents:, currency: "sar", key: nil)
    opts = key ? { idempotency_key: key } : {}   # retrying create returns the same intent
    Stripe::PaymentIntent.create(
      {
        amount: amount_cents,
        currency: currency,
        metadata: { customer_ref: customer_ref, purpose: "wallet_topup" },
        automatic_payment_methods: { enabled: true, allow_redirects: "never" }
      },
      opts
    )
  end

  # Same idea for paying for an order directly by card. The order is marked paid
  # ONLY on the webhook, never here — the money isn't real until Stripe says so.
  def self.create_order_intent(order:, currency: "sar", key: nil)
    opts = key ? { idempotency_key: key } : {}
    Stripe::PaymentIntent.create(
      {
        amount: order.total_cents,
        currency: currency,
        metadata: { customer_ref: order.customer.ref, purpose: "coffee_order", order_id: order.id },
        automatic_payment_methods: { enabled: true, allow_redirects: "never" }
      },
      opts
    )
  end
end
