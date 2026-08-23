require "test_helper"

class ReconciliationControllerTest < ActionDispatch::IntegrationTest
  # The public exhibit page must render, including the webhook-inbox panel.
  # With no Stripe key in test, the Stripe walk returns empty and the page still
  # shows a clean reconcile.
  test "renders with the webhook inbox panel" do
    customer = Customer.create!(name: "Test", ref: "recon-#{SecureRandom.hex(3)}")
    post switch_customer_path(customer.ref)   # the layout nav needs a current customer
    StripeEvent.create!(event_id: "evt_ok", event_type: "payment_intent.succeeded", status: "processed")
    StripeEvent.create!(event_id: "evt_bad", event_type: "payment_intent.succeeded", status: "failed", error: "boom")

    get reconciliation_path
    assert_response :ok
    assert_select "p", text: /Webhook inbox/
  end
end
