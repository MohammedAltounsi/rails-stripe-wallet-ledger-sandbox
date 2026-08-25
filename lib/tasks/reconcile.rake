desc "Reconcile the ledger against Stripe; exits non-zero on any drift (CI-friendly)"
task reconcile: :environment do
  r = ReconciliationService.run

  if r.unreachable?
    puts ""
    puts "  DALLAH — LEDGER RECONCILIATION"
    puts "  " + ("─" * 46)
    puts "  Stripe unreachable — could not match the ledger against Stripe."
    puts "  Internal invariants: #{r.invariants_hold? ? 'hold' : 'FAILED'}"
    puts "  " + ("─" * 46)
    puts ""
    # Exit 2 (not 1): "could not check", distinct from a real drift, so CI can
    # treat a Stripe outage differently from a ledger discrepancy.
    exit(r.invariants_hold? ? 2 : 1)
  end

  puts ""
  puts "  DALLAH — LEDGER RECONCILIATION"
  puts "  " + ("─" * 46)
  puts "  Stripe payments (ours):   #{r.stripe_count}"
  puts "  Matched to ledger:        #{r.matched}"
  puts "  Every entry balances:     #{r.unbalanced_entries.empty? ? 'yes' : "NO (#{r.unbalanced_entries.size})"}"
  puts "  Ledger sums to zero:      #{r.global_sum_cents.zero? ? 'yes' : "NO (#{r.global_sum_cents})"}"
  puts "  " + ("─" * 46)

  if r.missing.any?
    puts "  ✗ MISSING IN LEDGER (Stripe charged, we didn't record):"
    r.missing.each { |m| puts "      #{m[:pi]}  #{'%.2f' % (m[:amount_cents]/100.0)} SAR  (#{m[:purpose]})" }
  end
  if r.mismatched.any?
    puts "  ✗ AMOUNT MISMATCH:"
    r.mismatched.each { |m| puts "      #{m[:pi]}  stripe #{m[:stripe_cents]}  ledger #{m[:ledger_cents]}" }
  end
  if r.orphans.any?
    puts "  ✗ ORPHAN CREDITS (in ledger, no Stripe charge):"
    r.orphans.each { |o| puts "      #{o[:pi]}  #{'%.2f' % (o[:ledger_cents]/100.0)} SAR  (#{o[:memo]})" }
  end

  puts ""
  if r.ok?
    puts "  ✓ CLEAN — ledger and Stripe agree to the halala."
    puts ""
  else
    puts "  ✗ DRIFT DETECTED — see above."
    puts ""
    exit 1
  end
end
