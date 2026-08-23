require "test_helper"

class Webhooks::StripeControllerTest < ActionDispatch::IntegrationTest
  SECRET = "whsec_test_secret"

  setup { ENV["STRIPE_WEBHOOK_SECRET"] = SECRET }

  # Sign a payload exactly the way Stripe does, so construct_event accepts it.
  def signed_headers(payload)
    ts  = Time.now.to_i
    sig = OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{ts}.#{payload}")
    { "Stripe-Signature" => "t=#{ts},v1=#{sig}", "CONTENT_TYPE" => "application/json" }
  end

  def succeeded_event(pi_id:, amount:, metadata:)
    {
      id: "evt_#{pi_id}",
      type: "payment_intent.succeeded",
      data: { object: { id: pi_id, amount: amount, metadata: metadata } }
    }.to_json
  end

  test "a verified wallet_topup credits the wallet once, even on redelivery" do
    payload = succeeded_event(pi_id: "pi_123", amount: 5000,
                              metadata: { customer_ref: "cust-1", purpose: "wallet_topup" })

    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    assert_response :ok
    wallet = Account.find_by!(name: "wallet:cust-1")
    assert_equal 5000, wallet.balance_cents

    # Stripe redelivers webhooks. Same PaymentIntent => must NOT credit twice.
    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    assert_response :ok
    assert_equal 5000, wallet.reload.balance_cents
  end

  test "a verified coffee_order marks the order paid and books revenue once" do
    customer = Customer.create!(name: "Test", ref: "test-#{SecureRandom.hex(3)}")
    order = customer.orders.create!(status: "pending", payment_method: "card", total_cents: 2200)
    payload = succeeded_event(pi_id: "pi_ord", amount: 2200,
                              metadata: { customer_ref: customer.ref, purpose: "coffee_order", order_id: order.id })

    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    assert_response :ok
    assert_equal "paid", order.reload.status
    assert_equal 2200, Ledger.account(Ledger::REVENUE_ACCOUNT).balance_cents

    # Redelivery must not double-book revenue or re-flip anything.
    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    assert_equal 2200, Ledger.account(Ledger::REVENUE_ACCOUNT).balance_cents
  end

  test "each event is recorded in the inbox and a redelivery is deduped" do
    payload = succeeded_event(pi_id: "pi_inbox", amount: 5000,
                              metadata: { customer_ref: "cust-2", purpose: "wallet_topup" })
    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)   # redelivery, same event id

    assert_equal 1, StripeEvent.where(event_id: "evt_pi_inbox").count, "one inbox row per event id"
    assert StripeEvent.find_by(event_id: "evt_pi_inbox").processed?
    assert_equal 5000, Account.find_by!(name: "wallet:cust-2").balance_cents, "credited exactly once"
  end

  test "a non-money event is recorded and acknowledged without moving money" do
    payload = { id: "evt_created", type: "payment_intent.created",
                data: { object: { id: "pi_x", amount: 5000, metadata: {} } } }.to_json
    assert_no_difference -> { Posting.count } do
      post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    end
    assert_response :ok
    assert StripeEvent.find_by(event_id: "evt_created").processed?
  end

  test "a forged signature is rejected and nothing is credited" do
    payload = succeeded_event(pi_id: "pi_999", amount: 9999,
                              metadata: { customer_ref: "hacker", purpose: "wallet_topup" })

    post "/webhooks/stripe", params: payload,
         headers: { "Stripe-Signature" => "t=1,v1=deadbeef", "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert_nil Account.find_by(name: "wallet:hacker")
  end
end
