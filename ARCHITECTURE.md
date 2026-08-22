# Architecture

Why this system is built the way it is. The README covers what it does; this
covers the decisions behind it and what I would change to run it at scale.

## The core model

Every movement of money is a double-entry ledger `Entry` with two or more
`Posting` rows that sum to zero. An account's balance is the sum of its
postings. Nothing stores a running balance.

```
Entry "wallet topup pi_123"
  posting  stripe:cash    -5000
  posting  wallet:layla   +5000
                          -----
                             0   <- every entry must sum to zero
```

That one rule (postings sum to zero, per entry and across the whole ledger)
is what makes the system auditable: if the global sum is ever non-zero, money
was created or destroyed, and reconciliation says so.

## Decisions and trade-offs

### 1. Balances are derived, never stored

`Account#balance_cents` sums the postings every time. There is no
`balance` column to update.

- **Why:** a stored balance is a second source of truth. The moment an update
  is missed, retried, or races another write, it disagrees with the postings
  and you cannot tell which is right. Deriving the balance means it cannot drift
  by construction.
- **Trade-off:** reads cost a `SUM` instead of a column lookup.
- **At scale:** keep the append-only log as the source of truth, add a cached
  balance as a materialized projection (a `balances` table updated in the same
  transaction, or a periodic rollup), and reconcile the cache against the log.
  The log stays authoritative; the cache is only an optimization.

### 2. Money is booked on the webhook, never on intent creation

Creating a Stripe `PaymentIntent` moves nothing in the ledger. The ledger entry
is written only when a signature-verified `payment_intent.succeeded` webhook
arrives.

- **Why:** the intent is a request, not a fact. Booking at creation would credit
  money for payments that were never completed. The webhook is the only event
  that means "Stripe actually took the money".
- **Trade-off:** the UI has to treat an order as pending until the webhook lands,
  so there is a short window between payment and confirmation.
- **At scale:** the webhook handler should record the raw event in a
  `processed_stripe_events` table (see #4) and enqueue the booking as a job, so a
  slow ledger write never times out Stripe's delivery and retries stay cheap.

### 3. Idempotency is enforced at the database, not just checked in code

`Ledger.post!(memo, lines, key:)` takes an idempotency key. The key has a unique
index. Posting does a fast-path check, then relies on the index and a
`rescue ActiveRecord::RecordNotUnique` for the race.

- **Why:** a check-then-insert has a gap. Two concurrent webhook redeliveries can
  both pass the check and both try to insert. The unique index is the real guard:
  the database lets exactly one win, the loser catches the violation and returns
  the winner's entry. Money moves once.
- **Trade-off:** the caller has to choose a stable key. For Stripe events the key
  is `stripe-pi:<payment_intent_id>`, which is naturally unique per charge.
- **At scale:** unchanged. This is the pattern; it holds under real concurrency.

### 4. The wallet spend is locked twice

Spending wallet balance runs inside one transaction that first row-locks the
wallet account (`SELECT ... FOR UPDATE` via `lock!`), re-reads the balance,
then debits. A Postgres deferred `CONSTRAINT TRIGGER` also rejects any wallet
balance that would go negative at commit.

- **Why:** without the lock, two concurrent checkouts both read the old balance,
  both pass the "enough funds?" check, and both debit (a time-of-check to
  time-of-use overdraw). The lock serializes them. The trigger is defense in
  depth: even if an application bug skips the check, the database refuses to
  commit a negative wallet.
- **Trade-off:** a global-per-wallet lock serializes that one wallet's spends.
  That is correct and, for one customer's own actions, not a throughput problem.
- **At scale:** the lock is already per-wallet-row, so different wallets never
  contend. If a single wallet ever needed high write throughput, the next step is
  batching or a command queue per wallet, not a coarser lock.

### 5. Money is integer minor units

Every amount is an integer count of halalas (1 SAR = 100 halalas). There are no
floats in the money path; the only division by 100 is display formatting.

- **Why:** floating point cannot represent most decimal money values exactly, so
  it accumulates rounding error. Integer minor units are exact.
- **Trade-off:** none worth mentioning. This is the standard for money.

### 6. Reconciliation is a first-class feature

`ReconciliationService` compares the ledger against Stripe's list of succeeded
intents and reports four failure modes: a charge Stripe made that the ledger
never recorded (dropped webhook), an amount that disagrees, a ledger credit with
no matching charge (money from nowhere), and any entry or the global sum that
fails to balance. It runs on a page and headless via `rails reconcile`, which
exits non-zero on drift so CI or a cron can page on it.

- **Why:** webhooks get dropped and code has bugs. A ledger you cannot check
  against the payment processor is a ledger you have to trust blindly.
- **At scale:** run it continuously against a rolling window instead of listing
  all intents, store each run's result, and alert on the first non-zero drift.

### 7. No login, session-scoped visibility (demo only)

Anyone can act as a seeded customer with no sign-in, so the payment flows are
easy to try. Orders and receipts are scoped to `session[:order_ids]`, so one
visitor never sees another's order (the one place a real email lives).

- **Why:** the goal is to show the money core, not an auth system. Removing login
  removes friction for a reviewer.
- **Production would differ:** real authentication and authorization, per-user
  accounts, and the ledger and reconciliation pages behind an admin role instead
  of public.

## What I would add for production

- A `processed_stripe_events` table keyed by event id, so every webhook (not just
  money events) is deduped and auditable, with booking done in a background job.
- A cached balance projection updated in the posting transaction, reconciled
  against the log (see #1).
- Continuous reconciliation over a rolling window with alerting, instead of an
  on-demand full scan.
- Partitioning or archiving for the `postings` table once it grows, since it is
  append-only and unbounded.
- Read replicas for the public ledger and reconciliation views.

## Testing

The suite proves the invariants rather than the happy path:

- `ledger_test` and `idempotency_test`: entries must balance, and a repeated key
  moves money once.
- `webhooks/stripe_controller_test`: a forged signature is rejected, and a
  redelivered event does not double-book.
- `wallet_checkout_test` and `wallet_concurrency_test`: the locked spend debits
  the right amount, and two concurrent spends cannot overdraw (the concurrency
  and trigger tests run on Postgres, where the lock and trigger are real).
- `reconciliation_service_test`: each drift mode (missing, mismatch, orphan) is
  detected, and a matching ledger reconciles clean.

CI runs the full suite on Postgres plus Brakeman and bundler-audit on every push.
