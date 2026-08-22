namespace :demo do
  desc "Fund each demo customer's Dallah Card with a random balance above SAR 50 (idempotent)."
  task fund: :environment do
    refs = %w[layla omar sara]

    refs.each do |ref|
      customer = Customer.find_by(ref: ref)
      next unless customer

      target_cents = rand(75..350) * 100            # SAR 75–350, whole riyals
      delta = target_cents - customer.wallet_balance_cents
      if delta.positive?
        # Same shape as a real Stripe top-up: pull cash in, credit the wallet.
        Ledger.post!(
          "demo card funding #{ref}",
          [[Ledger.account(Ledger::CASH_ACCOUNT), -delta],
           [customer.wallet_account, delta]],
          key: "demo-fund:#{ref}"
        )
      end
      puts format("  %-6s → SAR %.2f", customer.name, customer.wallet_balance_cents / 100.0)
    end

    # Money-path checks: every demo card above SAR 50, books still balanced.
    Customer.where(ref: refs).find_each do |c|
      raise "#{c.ref} not funded above SAR 50 (#{c.wallet_balance_cents}¢)" unless c.wallet_balance_cents > 5000
    end
    sum = Posting.sum(:amount_cents)
    raise "ledger does not sum to zero (#{sum})" unless sum.zero?

    puts "OK — all demo cards above SAR 50, ledger balanced (sum=#{sum})."
  end
end
