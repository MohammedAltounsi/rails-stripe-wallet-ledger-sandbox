require "test_helper"

# The recovery sweep is what saves money that a failed webhook would otherwise
# strand once Stripe stops retrying. It must replay a stored event through the
# same idempotent path, book it once, and never double-book one that succeeded.
class ReprocessStuckStripeEventsJobTest < ActiveSupport::TestCase
  def event_payload(pi_id:, amount:, metadata:)
    {
      id: "evt_#{pi_id}",
      type: "payment_intent.succeeded",
      data: { object: { id: pi_id, amount: amount, metadata: metadata } }
    }.to_json
  end

  test "a failed inbox event is reprocessed and its money is booked once" do
    payload = event_payload(pi_id: "pi_stuck", amount: 5000,
                            metadata: { customer_ref: "sweep-1", purpose: "wallet_topup" })
    StripeEvent.create!(event_id: "evt_pi_stuck", event_type: "payment_intent.succeeded",
                        payload: payload, status: "failed", error: "boom")

    n = ReprocessStuckStripeEventsJob.perform_now

    assert_equal 1, n
    assert StripeEvent.find_by(event_id: "evt_pi_stuck").processed?
    assert_equal 5000, Account.find_by!(name: "wallet:sweep-1").balance_cents
    assert_equal 0, Posting.sum(:amount_cents), "book still sums to zero"
  end

  test "reprocessing an event that already posted does not double-book" do
    payload = event_payload(pi_id: "pi_once", amount: 3000,
                            metadata: { customer_ref: "sweep-2", purpose: "wallet_topup" })
    StripeEvent.create!(event_id: "evt_pi_once", event_type: "payment_intent.succeeded",
                        payload: payload, status: "received")

    ReprocessStuckStripeEventsJob.perform_now   # books it
    ReprocessStuckStripeEventsJob.perform_now   # would run again if it weren't idempotent

    assert_equal 3000, Account.find_by!(name: "wallet:sweep-2").balance_cents, "credited exactly once"
  end

  test "an already-processed event is left alone" do
    StripeEvent.create!(event_id: "evt_done", event_type: "payment_intent.succeeded",
                        payload: "{}", status: "processed", processed_at: Time.current)

    assert_equal 0, ReprocessStuckStripeEventsJob.perform_now, "processed events are not swept"
  end
end
