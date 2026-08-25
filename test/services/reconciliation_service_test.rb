require "test_helper"

# Reconciliation is the safety net a payments team gets paged for, so it needs
# its own test. Stripe is injected (no network): run(stripe:) takes a controlled
# list, while the ledger is read for real from rows seeded exactly as the webhook
# books them, an entry keyed "stripe-pi:<id>" whose positive posting is the amount.
class ReconciliationServiceTest < ActiveSupport::TestCase
  def book(pi_id, amount)
    Ledger.post!("stripe #{pi_id}",
      [[Ledger.account(Ledger::CASH_ACCOUNT), -amount],
       [Account.create!(name: "wallet:recon-#{pi_id}"), +amount]],
      key: "stripe-pi:#{pi_id}")
  end

  test "a ledger that matches Stripe reconciles clean" do
    book("pi_a", 5000)
    book("pi_b", 2200)

    result = ReconciliationService.run(stripe: {
      "pi_a" => { amount: 5000, purpose: "wallet_topup" },
      "pi_b" => { amount: 2200, purpose: "coffee_order" }
    })

    assert_equal 2, result.matched
    assert_empty result.missing
    assert_empty result.mismatched
    assert_empty result.orphans
    assert_empty result.unbalanced_entries
    assert_equal 0, result.global_sum_cents
    assert result.ok?, "a matching ledger should reconcile"
  end

  test "it flags a dropped webhook, a wrong amount, and an orphan credit" do
    book("pi_match",  5000)   # correct, in both
    book("pi_wrong",  4000)   # ledger booked 4000, Stripe charged 5000
    book("pi_orphan", 3000)   # in the ledger, no matching Stripe charge

    result = ReconciliationService.run(stripe: {
      "pi_match"   => { amount: 5000, purpose: "wallet_topup" },
      "pi_wrong"   => { amount: 5000, purpose: "wallet_topup" },
      "pi_missing" => { amount: 1800, purpose: "coffee_order" }  # Stripe charged, ledger never booked it
    })

    assert_equal 1, result.matched
    assert_equal ["pi_missing"], result.missing.map { |m| m[:pi] }
    assert_equal ["pi_wrong"],   result.mismatched.map { |m| m[:pi] }
    assert_equal 5000, result.mismatched.first[:stripe_cents]
    assert_equal 4000, result.mismatched.first[:ledger_cents]
    assert_includes result.orphans.map { |o| o[:pi] }, "pi_orphan"
    refute result.ok?, "missing, mismatch, or orphan must fail reconciliation"
  end

  test "when Stripe is unreachable it does not flag every ledger entry as an orphan" do
    book("pi_real", 5000)   # a real, correctly-booked credit

    result = ReconciliationService.run(stripe: {}, reachable: false)

    assert result.unreachable?, "should report the Stripe outage"
    refute result.ok?, "an unchecked run is not 'clean'"
    assert_empty result.orphans, "must NOT call a real entry an orphan just because Stripe was down"
    assert_empty result.missing
    assert result.invariants_hold?, "internal invariants are still checked"
  end
end
