require "test_helper"

# The wallet-overdraft guarantee has two layers, and BOTH are PostgreSQL-only:
#   1. app layer  — pay_with_wallet locks the wallet row (SELECT ... FOR UPDATE)
#      so two concurrent spends serialize instead of both reading a stale balance.
#   2. db layer   — the wallet_no_overdraft deferred trigger (db_constraints.rake)
#      rejects, at COMMIT, any change that would leave a wallet:* balance negative.
#
# SQLite (the local dev/test default) has neither, so these tests skip there. CI
# runs the suite against Postgres with the triggers installed, so they execute and
# actually prove the guarantee the README headlines. Threads need real committed
# rows, so transactional fixtures are off for this class.
class WalletConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  POSTGRES = ActiveRecord::Base.connection.adapter_name.match?(/postg/i)
  DRINK    = 1800   # one drink, in halalas

  setup do
    skip "wallet overdraft guarantees are PostgreSQL-only" unless POSTGRES
    @customer = Customer.create!(name: "Race", ref: "race-#{SecureRandom.hex(4)}", email: "r@example.com")
    @wallet   = @customer.wallet_account
    @revenue  = Ledger.account(Ledger::REVENUE_ACCOUNT)
    # Fund exactly one drink. Two concurrent spends must not both succeed.
    Ledger.post!("fund #{@customer.ref}",
      [[Ledger.account(Ledger::CASH_ACCOUNT), -DRINK], [@wallet, DRINK]],
      key: "fund-#{@customer.ref}")
  end

  # Layer 2: the DB trigger is the ultimate backstop, independent of app code.
  test "the overdraft trigger rejects a commit that drives a wallet negative" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Ledger.post!("overdraw #{@customer.ref}",
        [[@wallet, -5000], [@revenue, 5000]],   # only DRINK available
        key: "overdraw-#{@customer.ref}")
    end
    assert_equal DRINK, @customer.wallet_balance_cents, "rejected post must leave the balance untouched"
  end

  # Layer 1: the row lock serializes two racing debits. Without it, both threads
  # read the same balance, both pass the check, and both debit -> overdraft.
  test "two concurrent locked debits cannot both succeed" do
    spend = lambda do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          w = Account.lock.find(@wallet.id)   # SELECT ... FOR UPDATE, same as wallet.lock!
          if w.balance_cents >= DRINK
            sleep 0.15                          # hold the lock so the other thread must contend
            Ledger.post!("race spend #{SecureRandom.hex(3)}",
              [[w, -DRINK], [@revenue, DRINK]],
              key: "race-#{SecureRandom.uuid}")
            :ok
          else
            :rejected
          end
        end
      rescue ActiveRecord::StatementInvalid
        :rejected                               # trigger caught it if the lock ever failed to serialize
      end
    end

    results = [Thread.new(&spend), Thread.new(&spend)].map(&:value)

    assert_equal 1, results.count(:ok), "exactly one debit should win, got #{results.inspect}"
    assert_equal 0, @customer.wallet_balance_cents, "one drink paid: #{DRINK} - #{DRINK} = 0, never negative"
  end
end
