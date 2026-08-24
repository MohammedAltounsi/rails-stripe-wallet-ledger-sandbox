# Runbook

What to do when `/reconciliation` or the webhook inbox reports a problem.
This is the operational counterpart to [ARCHITECTURE.md](ARCHITECTURE.md),
written for whoever is on call, not whoever is reading the code.

## "Reconciliation shows drift"

`/reconciliation` (or `bin/rails reconcile`, which exits non-zero; wire it
into a scheduled check) compares the ledger against Stripe's list of
succeeded PaymentIntents. It reports one of three things:

### Missing: Stripe charged the card, the ledger never recorded it

Cause: a `payment_intent.succeeded` webhook was never delivered, or was
delivered and failed silently before the inbox existed to catch it. Money
was taken from a customer but nothing here reflects it, so this is the one
to act on first.

1. Find the PaymentIntent in the Stripe Dashboard by its ID.
2. Check `StripeEvent` for that event. If it's `failed`, read `.error` and
   fix the root cause, then resend the event from the Stripe Dashboard
   (Developers → Webhooks → the endpoint → find the event → "Resend").
3. If no `StripeEvent` row exists at all, the webhook never reached us
   (endpoint down, wrong URL, or an infra-level 5xx before app code ran).
   Resending from the Stripe Dashboard replays it through the same
   idempotent path, safe because both `credit_wallet` and `settle_order` are
   keyed on the PaymentIntent ID and no-op if already applied.

### Mismatched: the ledger recorded a different amount than Stripe charged

For a wallet top-up this should be structurally impossible (the amount comes
straight from the PaymentIntent). For a card order, `settle_order` already
guards this at the source: if `pi.amount != order.total_cents`, it logs an
error and deliberately books nothing, leaving the order `pending` rather
than recording the wrong revenue. If reconciliation later reports a
mismatch anyway, treat it as a data integrity incident, not routine drift:

1. Pull the `Entry` for `stripe-pi:<id>` and the Stripe PaymentIntent side by
   side.
2. Do NOT re-run reconciliation to "fix" it. It only reports, it never
   writes. Correct the ledger by hand with a new, explicitly-memo'd
   correcting entry (never edit a posting after the fact).

### Orphan: a ledger credit with no matching Stripe charge

The scary one: money appeared in a wallet with nothing on Stripe's side to
back it. Treat as a security incident first, bug second:

1. Check the `Entry`'s `idempotency_key`. If it isn't shaped like
   `stripe-pi:pi_...`, something posted to the ledger outside the normal
   webhook path (a console session, a bypassed check).
2. Audit recent deploys and console access before assuming it's a Stripe-side
   anomaly.

## "An order is stuck `pending` with a card payment"

This is the amount-mismatch guard in `settle_order` doing its job: the
webhook arrived, but `pi.amount` didn't match `order.total_cents`, so it
refused to auto-settle rather than record the wrong revenue. Check the log
line it leaves (`settle_order amount mismatch: ...`), compare the two
amounts, and settle the order manually once you've confirmed which one is
right. This should only happen if the order's price changed between page
load and payment; it should not happen from a stable menu.

## "The wallet-overdraft trigger rejected a commit"

This is the system working. It means app code (a bug, or a direct console
`Ledger.post!`) tried to commit a wallet balance below zero. Read the
`ActiveRecord::StatementInvalid` message; it names the wallet and the
balance. Do not disable or loosen the trigger to unblock it; fix the caller.
The app-level lock in `CheckoutController#pay_with_wallet` should make this
unreachable in normal use; if it fires, something bypassed that method.

## "A checkout appears to have charged twice"

It didn't; check `orders.checkout_token` first. A double-tap or a retried
POST reuses the same token (stored in the session), the unique index
rejects the second insert, `ActiveRecord::RecordNotUnique` is caught in
`CheckoutController#create`, and the shopper is redirected to the existing
order instead of a new one being created. If two *different* orders exist
for what was actually one checkout, the token was lost between requests
(session dropped) rather than a Rails bug; check for that first.

## Issuing test payments from the command line

The Stripe CLI is the intended tool here, not a raw `curl`, since the
checkout and top-up forms are session-backed and CSRF-protected:

```bash
stripe trigger payment_intent.succeeded
```

For a real end-to-end smoke test after a deploy, use the live site with the
test card `4242 4242 4242 4242`, any future expiry, any CVC, exactly as a
real shopper would.
