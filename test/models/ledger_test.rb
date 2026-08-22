require "test_helper"

class LedgerTest < ActiveSupport::TestCase
  setup do
    @wallet = Account.create!(name: "wallet:customer-1")
    @cash   = Account.create!(name: "cash:stripe")
  end

  test "a balanced entry posts and moves money" do
    # Customer tops up 50.00 SAR (5000 halalas): out of cash, into wallet.
    Ledger.post!("top up 50 SAR", [[@cash, -5000], [@wallet, +5000]])

    assert_equal(-5000, @cash.balance_cents)
    assert_equal(+5000, @wallet.balance_cents)
  end

  test "an unbalanced entry is refused and nothing is written" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Ledger.post!("bad", [[@cash, -5000], [@wallet, +4000]]) # 1000 would vanish
    end

    # The whole entry rolled back — no phantom money anywhere.
    assert_equal 0, Posting.count
    assert_equal 0, @wallet.balance_cents
  end

  test "the golden invariant: every posting in the whole ledger sums to zero" do
    Ledger.post!("top up 50 SAR",      [[@cash, -5000], [@wallet, +5000]])
    Ledger.post!("buy coffee 12 SAR",  [[@wallet, -1200], [@cash, +1200]])

    assert_equal 0, Posting.sum(:amount_cents)
  end
end
