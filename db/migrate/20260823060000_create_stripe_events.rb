class CreateStripeEvents < ActiveRecord::Migration[8.1]
  # The webhook inbox: one row per Stripe event, deduped on the event id. It makes
  # webhook handling exactly-once at the EVENT level (not just per PaymentIntent),
  # gives an audit trail of everything Stripe sent, and records failures so a
  # redelivery can safely reprocess them.
  def change
    create_table :stripe_events do |t|
      t.string   :event_id,   null: false
      t.string   :event_type, null: false
      t.string   :status,     null: false, default: "received"
      t.text     :payload
      t.text     :error
      t.datetime :processed_at
      t.timestamps
    end
    add_index :stripe_events, :event_id, unique: true
  end
end
