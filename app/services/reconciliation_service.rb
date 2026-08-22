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
    :unbalanced_entries, :global_sum_cents,
    keyword_init: true
  ) do
    def ok?
      missing.empty? && mismatched.empty? && orphans.empty? &&
        unbalanced_entries.empty? && global_sum_cents.zero?
    end
  end

  # stripe/ledger are injectable so the diff logic can be tested without the
  # network; in production both default to the real fetchers.
  def self.run(stripe: fetch_succeeded_intents, ledger: ledger_entries_by_pi)
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
      unbalanced_entries: Entry.all.reject { |e| e.postings.sum(&:amount_cents).zero? }.map(&:id),
      global_sum_cents:   Posting.sum(:amount_cents)
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

  def self.fetch_succeeded_intents
    out = {}
    Stripe::PaymentIntent.list(limit: 100).auto_paging_each do |pi|
      next unless pi.status == "succeeded"
      out[pi.id] = { amount: pi.amount, purpose: pi.metadata["purpose"] }
    end
    out
  rescue Stripe::StripeError => e
    Rails.logger.warn("Reconciliation: could not reach Stripe: #{e.message}")
    out
  end
end
