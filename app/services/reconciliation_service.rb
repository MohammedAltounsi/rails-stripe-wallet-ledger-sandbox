# Reconciliation: the safety net a payments team actually gets paged for.
#
# It answers one question — "does our ledger agree with Stripe, to the halala?"
# Three ways money can silently go wrong, all caught here:
#
#   missing     Stripe charged the card but our ledger never recorded it
#               (a dropped webhook). We owe someone money we didn't book.
#   mismatched  We recorded a different amount than Stripe actually charged.
#   orphan      Our ledger credited a wallet with NO matching Stripe charge.
#               (the scary one — money appearing from nowhere.)
#
# Plus two internal invariants that must always hold:
#   - every entry balances (its postings sum to zero)
#   - the whole ledger sums to zero (money is only moved, never created)
module ReconciliationService
  PURPOSES = %w[wallet_topup coffee_order].freeze

  Result = Struct.new(
    :stripe_count, :matched, :missing, :mismatched, :orphans,
    :unbalanced_entries, :global_sum_cents, :reachable,
    keyword_init: true
  ) do
    # Could not reach Stripe, so the ledger-vs-Stripe diff was skipped. The
    # internal invariants below were still checked.
    def unreachable? = !reachable

    # The two checks that need no network: every entry balances, and the whole
    # book sums to zero. These hold (or fail) whether or not Stripe is up.
    def invariants_hold? = unbalanced_entries.empty? && global_sum_cents.zero?

    # Clean means we actually checked against Stripe and found no drift. An
    # unreachable run is not clean and not drift — it is "not checked yet".
    def ok? = reachable && missing.empty? && mismatched.empty? && orphans.empty? && invariants_hold?
  end

  # stripe/ledger are injectable so the diff logic can be tested without the
  # network; in production stripe comes from the reachability-aware fetcher. An
  # injected stripe hash is treated as reachable unless reachable: is given.
  def self.run(stripe: nil, reachable: nil, ledger: ledger_entries_by_pi)
    if stripe.nil?
      fetched   = fetch_succeeded_intents
      stripe    = fetched[:intents]
      reachable = fetched[:reachable]
    end
    reachable = true if reachable.nil?

    unbalanced = Entry.all.reject { |e| e.postings.sum(&:amount_cents).zero? }.map(&:id)
    global_sum = Posting.sum(:amount_cents)

    # Stripe is down: DO NOT diff. A missing or partial Stripe list would mark
    # every real ledger entry an "orphan" (money from nowhere) — a false-alarm
    # storm. Report the internal invariants and that the match could not run.
    unless reachable
      return Result.new(
        stripe_count: 0, matched: 0, missing: [], mismatched: [], orphans: [],
        unbalanced_entries: unbalanced, global_sum_cents: global_sum, reachable: false
      )
    end

    missing = []; mismatched = []; matched = 0
    stripe.each do |id, info|
      next unless PURPOSES.include?(info[:purpose])
      entry = ledger[id]
      if entry.nil?
        missing << { pi: id, amount_cents: info[:amount], purpose: info[:purpose] }
      elsif credited(entry) != info[:amount]
        mismatched << { pi: id, stripe_cents: info[:amount], ledger_cents: credited(entry) }
      else
        matched += 1
      end
    end

    orphans = ledger.reject { |id, _| stripe.key?(id) }.map do |id, entry|
      { pi: id, ledger_cents: credited(entry), memo: entry.memo }
    end

    Result.new(
      stripe_count:       stripe.count { |_, i| PURPOSES.include?(i[:purpose]) },
      matched:            matched,
      missing:            missing,
      mismatched:         mismatched,
      orphans:            orphans,
      unbalanced_entries: unbalanced,
      global_sum_cents:   global_sum,
      reachable:          true
    )
  end

  # The amount an entry credited = the sum of its positive postings.
  def self.credited(entry)
    entry.postings.map(&:amount_cents).select { |c| c > 0 }.sum
  end

  def self.ledger_entries_by_pi
    Entry.where("idempotency_key LIKE ?", "stripe-pi:%").includes(:postings).each_with_object({}) do |e, h|
      h[e.idempotency_key.delete_prefix("stripe-pi:")] = e
    end
  end

  # Returns { intents:, reachable: }. reachable is false when Stripe could not be
  # reached, so run can skip the diff instead of treating an empty list as "every
  # ledger entry is an orphan".
  def self.fetch_succeeded_intents
    out = {}
    Stripe::PaymentIntent.list(limit: 100).auto_paging_each do |pi|
      next unless pi.status == "succeeded"
      out[pi.id] = { amount: pi.amount, purpose: pi.metadata["purpose"] }
    end
    { intents: out, reachable: true }
  rescue Stripe::StripeError => e
    Rails.logger.warn("Reconciliation: could not reach Stripe: #{e.message}")
    { intents: {}, reachable: false }
  end
end
