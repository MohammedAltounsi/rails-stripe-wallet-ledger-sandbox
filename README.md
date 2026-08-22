# Dallah — payments & wallet, in Ruby on Rails

A working coffee storefront built around a **double-entry ledger**, **real Stripe payments**,
and a **reconciliation job** that proves the books never drift. Everything runs in Stripe **test
mode** — no real money moves.

It exists to show the skills a Payments & Wallet backend role needs, end to end: taking money,
storing value, spending it, and being able to prove afterwards that the ledger agrees with the
payment processor to the halala.

---

## What it demonstrates

| Concept | Where it lives | Why it matters |
|---|---|---|
| **Double-entry ledger** | `app/models/ledger.rb`, `entry.rb`, `posting.rb`, `account.rb` | Money is only ever *moved*, never created. Every entry's postings sum to zero; balances are *derived* from an append-only log, never stored, so they can't drift. |
| **Idempotency** | `Ledger.post!(key:)` + a unique DB index | A retried request or a redelivered webhook credits the wallet exactly once. |
| **Stripe integration** | `app/models/stripe_gateway.rb`, `stripe_payment_controller.js` | Real PaymentIntents via the embedded Payment Element (test card). |
| **Webhook discipline** | `app/controllers/webhooks/stripe_controller.rb` | Signature-verified. Credits **only** on `payment_intent.succeeded` — "create ≠ credit". Handles Stripe's at-least-once delivery without double-crediting. |
| **Wallet + direct card** | `wallet_controller.rb`, `checkout_controller.rb` | Top up a stored-value wallet, spend from it (with an insufficient-funds guard), or pay an order directly by card. |
| **Reconciliation** | `app/services/reconciliation_service.rb`, `lib/tasks/reconcile.rake` | Compares the ledger against Stripe and flags three failure modes: a charge with no ledger entry (dropped webhook), an amount mismatch, and an orphan credit with no charge. |

Stack: Rails 8.1, Hotwire (Turbo + Stimulus), Tailwind, SQLite, the `stripe` gem.

---

## The money rules (the important part)

1. **One entry point.** All money moves through `Ledger.post!(memo, lines, key:)`. Nothing else
   writes a posting.
2. **Every entry balances.** `lines` must sum to zero, enforced before the entry saves. An
   unbalanced entry raises and rolls back — no half-written money.
3. **Balances are derived.** `Account#balance_cents` sums postings. There is no stored balance to
   fall out of sync.
4. **The webhook is the source of truth.** Creating a PaymentIntent moves no money. The wallet is
   credited / the order marked paid only when Stripe confirms the charge.
5. **Money is integer minor units.** Halalas, never floats.

Movements:

```
Top up (card)     stripe:cash −X   wallet:<ref> +X
Pay from wallet   wallet:<ref> −X  revenue:coffee +X
Pay by card       stripe:cash −X   revenue:coffee +X
```

Each line sums to zero, so the whole ledger always sums to zero — verifiable on `/ledger`.

---

## Run it

Prerequisites: Ruby 4.0+, the [Stripe CLI](https://stripe.com/docs/stripe-cli), and a Stripe
**test** account.

```
bundle install
bin/rails db:setup            # migrate + seed the menu and demo customers
```

Put your Stripe **test** keys in `.env.local` (gitignored):

```
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...   # printed by `stripe listen`, below
```

Start the app and the webhook tunnel in two shells:

```
bin/rails server
stripe listen --forward-to localhost:3000/webhooks/stripe
```

Copy the `whsec_...` the tunnel prints into `.env.local`, restart the server, then open
<http://localhost:3000>.

> Windows: run Rails commands as `ruby bin\rails ...`.

---

## Try it

- **Shop** — add coffees at `/`, check out at `/checkout`.
- **Top up** — `/wallet`, pay with test card `4242 4242 4242 4242`, any future date, any CVC.
- **Pay from wallet** or **by card** at checkout; receipt at `/orders/:id`.
- **Ledger** — `/ledger` shows every account, the derived balances, and the zero-sum proof.
- **Reconciliation** — `/reconciliation` in the browser, or headless:

```
bin/rails reconcile           # prints the report; exits non-zero on any drift (wire into CI)
```

To see reconciliation catch a problem: delete a `stripe-pi:*` entry (a simulated dropped webhook)
and run `reconcile` — it reports the exact missing PaymentIntent. Replaying the credit through
`Ledger.post!` with the same key restores it.

---

## Tests

```
bin/rails test test/models        # ledger invariants + idempotency
bin/rails test test/controllers   # webhook signature verification + idempotent crediting
```
