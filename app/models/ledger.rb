module Ledger
  # Named system accounts, so a typo can't silently open a second account.
  CASH_ACCOUNT    = "stripe:cash"    # external money pulled in via Stripe (an asset source)
  REVENUE_ACCOUNT = "revenue:coffee" # coffee sales

  def self.account(name)
    Account.find_or_create_by!(name: name)
  end

  # The ONLY way money moves. Give it a memo and the lines that move.
  # lines = [[account, amount_cents], ...]  — amounts must sum to zero.
  #
  # key: an optional idempotency key. Pass the same key twice (a retry, a
  # double-tap, a webhook redelivery) and the money moves ONCE — the first
  # entry is returned again instead of a duplicate being created. This is the
  # single most important rule in real payments: a retry must never double-charge.
  #
  # Everything happens inside one DB transaction: either every posting lands,
  # or none do. That atomicity is why a crash mid-write can't leak money.
  #
  # Balance is enforced twice: in Ruby by Entry#must_balance on every save, and in
  # Postgres by a deferred CONSTRAINT TRIGGER (lib/tasks/db_constraints.rake) that
  # rejects any unbalanced entry at COMMIT, even if the app layer has a bug.
  def self.post!(memo, lines, key: nil)
    # Fast path: we already did this exact movement — replay the first result.
    if key && (existing = Entry.find_by(idempotency_key: key))
      return existing
    end

    Entry.transaction do
      entry = Entry.new(memo: memo, idempotency_key: key)
      lines.each { |account, cents| entry.postings.build(account: account, amount_cents: cents) }
      entry.save!   # must_balance runs here; unbalanced => raises => rolls back
      entry
    end
  rescue ActiveRecord::RecordNotUnique
    # Race: another request inserted the same key between our check and our save.
    # The unique index caught it and rolled us back. The winner already exists —
    # return it. Money still moved exactly once.
    Entry.find_by!(idempotency_key: key)
  end
end
