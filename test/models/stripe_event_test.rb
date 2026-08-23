require "test_helper"

# The webhook inbox: recorded once per event id, deduped on redelivery, and a
# failed event stays reprocessable so Stripe's retry can heal it.
class StripeEventTest < ActiveSupport::TestCase
  Fake = Struct.new(:id, :type)

  test "record is idempotent: a redelivered event id returns the same row" do
    e = Fake.new("evt_1", "payment_intent.succeeded")
    first  = StripeEvent.record(e, "{}")
    second = StripeEvent.record(e, "{}")
    assert_equal first.id, second.id
    assert_equal 1, StripeEvent.where(event_id: "evt_1").count
  end

  test "a failed event is not processed, so a retry will reprocess it" do
    row = StripeEvent.record(Fake.new("evt_2", "payment_intent.succeeded"), "{}")
    row.mark_failed!("boom")
    assert_equal "failed", row.status
    refute row.processed?, "a failed event must be reprocessable, not skipped"
    assert_equal "boom", row.reload.error
  end

  test "mark_processed! flips status, stamps the time, clears any error" do
    row = StripeEvent.record(Fake.new("evt_3", "payment_intent.succeeded"), "{}")
    row.mark_failed!("transient")
    row.mark_processed!
    assert row.processed?
    assert_not_nil row.processed_at
    assert_nil row.error
  end
end
