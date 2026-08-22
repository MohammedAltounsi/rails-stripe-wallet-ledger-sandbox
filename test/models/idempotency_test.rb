require "test_helper"

class IdempotencyTest < ActiveSupport::TestCase
  setup do
    @cash   = Account.create!(name: "cash")
    @wallet = Account.create!(name: "wallet")
  end

  test "same idempotency key moves money only once" do
    key = "topup-abc-123"
    e1 = Ledger.post!("top up 50 SAR", [[@cash, -5000], [@wallet, 5000]], key: key)
    e2 = Ledger.post!("top up 50 SAR", [[@cash, -5000], [@wallet, 5000]], key: key) # retry

    assert_equal e1.id, e2.id                                  # same entry, not a new one
    assert_equal 1, Entry.where(idempotency_key: key).count
    assert_equal 5000, @wallet.balance_cents                   # charged once, not twice
  end

  test "different keys post separately" do
    Ledger.post!("t1", [[@cash, -5000], [@wallet, 5000]], key: "k1")
    Ledger.post!("t2", [[@cash, -3000], [@wallet, 3000]], key: "k2")
    assert_equal 8000, @wallet.balance_cents
  end

  test "no key still works — each call is its own entry" do
    Ledger.post!("t", [[@cash, -1000], [@wallet, 1000]])
    Ledger.post!("t", [[@cash, -1000], [@wallet, 1000]])
    assert_equal 2000, @wallet.balance_cents
  end

  test "the DB unique index is the real guard against duplicates" do
    Entry.create!(memo: "first", idempotency_key: "dup")
    assert_raises(ActiveRecord::RecordNotUnique) do
      # bypass Rails validations to prove the DATABASE itself refuses the dupe
      Entry.new(memo: "second", idempotency_key: "dup").save!(validate: false)
    end
  end
end
