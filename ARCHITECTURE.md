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

Postings sum to zero in each entry and across the whole ledger. If the
global sum is ever non-zero, money was created or lost somewhere, and
reconciliation reports it.

## Decisions and trade-offs

### 1. Balances are computed from postings

`Account#balance_cents` sums the postings every time. There is no
`balance` column to update.

- **Why:** a stored balance is a second copy of the data. If an update is
  missed, retried, or races another write, it disagrees with the postings and
  you can't tell which one is right. A balance computed from the postings
  can't drift.
- **Trade-off:** reads cost a `SUM` instead of a column lookup.
- **At scale:** keep the append-only log as the source of truth, add a cached
  balance as a materialized projection (a `balances` table updated in the same
  transaction, or a periodic rollup), and reconcile the cache against the log.
  The log stays the source of truth, and the cache only speeds up reads.

### 2. Money is booked when the webhook arrives

Creating a Stripe `PaymentIntent` moves nothing in the ledger. The ledger entry
is written only when a signature-verified `payment_intent.succeeded` webhook
arrives.

- **Why:** an intent is only a request to charge. Booking at creation would credit
  money for payments that were never completed. The webhook is the only event
  that means "Stripe actually took the money".
- **Trade-off:** the UI has to treat an order as pending until the webhook lands,
  so there is a short window between payment and confirmation.
- **How redelivery is handled:** every event is recorded once in a webhook inbox
  (see #3). A redelivery of an already-processed event returns 200 without
  touching money; a processing failure is recorded and returns 500 so Stripe
  retries, and the retry reprocesses safely.

### 3. Webhooks are exactly-once via an inbox

Every Stripe event is written to a `stripe_events` inbox, deduped on a unique
`event_id`. The handler processes an event only if its inbox row is not already
`processed`; on success it marks it processed, on failure it marks it failed and
returns 500 so Stripe redelivers.

- **Why:** Stripe delivers at-least-once. Deduping only on the PaymentIntent
  covers money, but not other events, and leaves no audit trail. The inbox
  processes each event once, records what arrived, and keeps a failed event so
  a retry can process it again.
- **Two layers:** the inbox dedupes at the event level; `Ledger.post!` (see #4)
  dedupes the money at the posting level. Either alone is safe; together they
  survive a crash between recording the event and booking the money.
- **Trade-off:** one extra write per event, which is cheap.

### 4. Idempotency is enforced by a unique index

`Ledger.post!(memo, lines, key:)` takes an idempotency key. The key has a unique
index. Posting does a fast-path check, then relies on the index and a
`rescue ActiveRecord::RecordNotUnique` for the race.

- **Why:** a check-then-insert has a gap. Two concurrent webhook redeliveries can
  both pass the check and both try to insert. The unique index is the real guard:
  the database lets exactly one win, the loser catches the violation and returns
  the winner's entry. Money moves once.
- **Trade-off:** the caller has to choose a stable key. For Stripe events the key
  is `stripe-pi:<payment_intent_id>`, which is naturally unique per charge.
- **At scale:** unchanged. This works under real concurrency.

### 5. The wallet spend is locked twice

Spending wallet balance runs inside one transaction that first row-locks the
wallet account (`SELECT ... FOR UPDATE` via `lock!`), re-reads the balance,
then debits. A Postgres deferred `CONSTRAINT TRIGGER` also rejects any wallet
balance that would go negative at commit.

- **Why:** without the lock, two concurrent checkouts both read the old balance,
  both pass the "enough funds?" check, and both debit (a time-of-check to
  time-of-use overdraw). The lock serializes them. The trigger is a second
  check: if an application bug skips the lock, the database still refuses to
  commit a negative wallet.
- **Trade-off:** a global-per-wallet lock serializes that one wallet's spends.
  That is correct and, for one customer's own actions, not a throughput problem.
- **At scale:** the lock is already per-wallet-row, so different wallets never
  contend. If a single wallet ever needed high write throughput, the next step is
  batching or a command queue per wallet, not a coarser lock.

### 6. Money is integer minor units

Every amount is an integer count of halalas (1 SAR = 100 halalas). There are no
floats in the money path; the only division by 100 is display formatting.

- **Why:** floating point cannot represent most decimal money values exactly, so
  it accumulates rounding error. Integer minor units are exact.
- **Trade-off:** none. This is standard practice for money.

### 7. Reconciliation is built in

`ReconciliationService` compares the ledger against Stripe's list of succeeded
intents and reports four failure modes: a charge Stripe made that the ledger
never recorded (dropped webhook), an amount that disagrees, a ledger credit with
no matching charge (money from nowhere), and any entry or the global sum that
fails to balance. It runs on a page and headless via `rails reconcile`, which
exits non-zero on drift so CI or a cron can page on it.

- **Why:** webhooks get dropped and code has bugs. Without a check against
  Stripe, there is no way to know when the ledger is wrong.
- **At scale:** run it continuously against a rolling window instead of listing
  all intents, store each run's result, and alert on the first non-zero drift.

### 8. No login, session-scoped visibility (demo only)

Anyone can act as a seeded customer with no sign-in, so the payment flows are
easy to try. Orders and receipts are scoped to `session[:order_ids]`, so one
visitor never sees another's order (the one place a real email lives).

- **Why:** the demo is meant to show the payment code. Without a login,
  someone reviewing it can try the flows right away.
- **Production would differ:** real authentication and authorization, per-user
  accounts, and the ledger and reconciliation pages behind an admin role instead
  of public.

## What I would add for production

- Move webhook booking into a background job off the inbox row, so a slow ledger
  write never times out Stripe's delivery (the inbox itself is already built, #3).
- A cached balance projection updated in the posting transaction, reconciled
  against the log (see #1).
- Continuous reconciliation over a rolling window with alerting, instead of an
  on-demand full scan.
- Partitioning or archiving for the `postings` table once it grows, since it is
  append-only and unbounded.
- Read replicas for the public ledger and reconciliation views.

## Testing

The suite tests the invariants and the failure cases:

- `ledger_test` and `idempotency_test`: entries must balance, and a repeated key
  moves money once.
- `webhooks/stripe_controller_test` and `stripe_event_test`: a forged signature
  is rejected, every event is recorded once, a redelivery does not double-book,
  and a failed event stays reprocessable.
- `wallet_checkout_test` and `wallet_concurrency_test`: the locked spend debits
  the right amount, and two concurrent spends cannot overdraw (the concurrency
  and trigger tests run on Postgres, where the lock and trigger are real).
- `reconciliation_service_test`: each drift mode (missing, mismatch, orphan) is
  detected, and a matching ledger reconciles clean.

CI runs the full suite on Postgres plus Brakeman and bundler-audit on every push.
