<div align="center">

# Dallah Coffee

A double-entry payments and wallet ledger, built in Rails 8.

[![CI](https://github.com/MohammedAltounsi/rails-stripe-wallet-ledger-sandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/MohammedAltounsi/rails-stripe-wallet-ledger-sandbox/actions/workflows/ci.yml)
![Ruby](https://img.shields.io/badge/Ruby-4.0-CC342D?logo=ruby&logoColor=white)
![Rails](https://img.shields.io/badge/Rails-8.1-CC0000?logo=rubyonrails&logoColor=white)
![Stripe](https://img.shields.io/badge/Stripe-test%20mode-635BFF?logo=stripe&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-informational)

### [▶ Open the live demo](https://dallah-coffee.onrender.com)

Stripe test mode, so no real card is charged. Pay with `4242 4242 4242 4242`, any future date, any CVC.

<br>

<img src="docs/screenshots/menu.png" alt="Dallah Coffee storefront" width="820">

</div>

A coffee-ordering app with a real money core. Customers top up a wallet, pay by
card or from that wallet, and every halala is tracked in a double-entry ledger
that can be checked against Stripe to the last unit.

## What it does

| Area | What happens | Where |
|---|---|---|
| Double-entry ledger | Every entry's postings sum to zero. Balances are summed from an append-only log, never stored, so they cannot drift. | `app/models/ledger.rb`, `account.rb` |
| Idempotency | A retried request or a redelivered webhook moves money once, enforced by an idempotency key and a unique index. | `Ledger.post!` |
| Stripe payments | Card charges via PaymentIntents and the embedded Payment Element. | `app/models/stripe_gateway.rb` |
| Webhooks | Signature-verified. The wallet is credited and the order marked paid only on `payment_intent.succeeded`. | `app/controllers/webhooks/stripe_controller.rb` |
| Wallet | Top up, then spend. The spend is row-locked, so two concurrent checkouts cannot overdraw it. | `checkout_controller.rb`, `wallet_controller.rb` |
| Reconciliation | Compares the ledger against Stripe and reports dropped webhooks, amount mismatches, and orphan credits. | `app/services/reconciliation_service.rb` |

## The exhibits

The ledger and reconciliation pages are public in the demo, because they are the
point. They show synthetic data only.

<table>
<tr>
<td width="50%">
<img src="docs/screenshots/ledger.png" alt="The double-entry ledger, summing to zero">
<p align="center"><b>The ledger</b><br>Balances derived from an append-only log. The whole thing sums to zero.</p>
</td>
<td width="50%">
<img src="docs/screenshots/reconciliation.png" alt="Reconciliation against Stripe">
<p align="center"><b>Reconciliation</b><br>Ledger vs Stripe, to the halala. Runs headless in CI and exits non-zero on drift.</p>
</td>
</tr>
<tr>
<td width="50%">
<img src="docs/screenshots/wallet.png" alt="Wallet balance and activity">
<p align="center"><b>The wallet</b><br>Prepaid balance, credited only by a verified webhook. Every top-up and spend is a ledger posting.</p>
</td>
<td width="50%" valign="middle">
<p align="center">Pay by card or straight from the wallet.<br>Either way the money lands in the same ledger, once.</p>
</td>
</tr>
</table>

## How it works

```mermaid
flowchart LR
    B[Browser · Hotwire] --> C[Controllers]
    C --> L[Ledger]
    C --> G[StripeGateway]
    G <--> S[Stripe]
    S -->|signed webhook| W[Webhooks]
    W --> L
    L --> DB[(PostgreSQL · balance triggers)]
```

Money moves through one method, `Ledger.post!(memo, lines, key:)`, inside a
transaction. The rules it enforces:

1. Every entry balances. Its lines must sum to zero, or it rolls back.
2. Balances are derived. `Account#balance_cents` sums postings; nothing is stored to fall out of sync.
3. The webhook is the source of truth. Creating a PaymentIntent moves no money; the charge is booked only when Stripe confirms it.
4. Money is integer halalas. No floats anywhere in the money path.
5. Postgres has the final say. A deferred trigger rejects any unbalanced entry or negative wallet balance, even if the app has a bug.

For the reasoning behind each decision and what would change at scale, see [ARCHITECTURE.md](ARCHITECTURE.md).
For what to do when reconciliation reports drift, see [RUNBOOK.md](RUNBOOK.md).

## Paying by card

```mermaid
sequenceDiagram
    actor Cust as Customer
    participant App as Rails
    participant Stripe
    participant Ledger
    Cust->>App: Checkout, pay by card
    App->>Stripe: Create PaymentIntent (idempotency key)
    App-->>Cust: Payment Element (test card)
    Cust->>Stripe: Confirm card
    Stripe-->>App: webhook payment_intent.succeeded (signed)
    App->>App: Verify signature
    App->>Ledger: post! (idempotent), book the money now
    App-->>Cust: Order marked paid
```

## Run it

Needs Ruby 4.0+, the [Stripe CLI](https://stripe.com/docs/stripe-cli), and a Stripe test account.

```bash
bundle install
bin/rails db:setup
```

Put your test keys in `.env.local` (gitignored):

```
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

Run the app and the webhook tunnel in two shells:

```bash
bin/rails server
stripe listen --forward-to localhost:3000/webhooks/stripe
```

Open <http://localhost:3000>. See the ledger at `/ledger` and reconciliation at `/reconciliation`.
Deployment notes are in [docs/DEPLOY.md](docs/DEPLOY.md).

## Tests

```bash
bin/rails test
```

Covers the ledger invariants, idempotent crediting, webhook signature checks, and
the locked wallet spend (no overdraft, no double-spend). Brakeman and bundler-audit
run on every push.

## Security

- Webhooks are signature-verified before any money moves.
- Content Security Policy with per-request script nonces, `force_ssl` with HSTS, and a host allowlist.
- rack-attack throttles the write endpoints.
- All secrets come from environment variables; the credentials key is never committed.
- Brakeman and bundler-audit gate every push in CI.

## Demo notes

Two things are open on purpose:

- Anyone can switch between the seeded customers with no login. Orders and receipts are scoped to the browser session, so one visitor never sees another's.
- `/ledger` and `/reconciliation` are public, because they are the exhibit. They show synthetic data only.

Both are safe under two rules: Stripe stays in test mode, and the seed data stays fictional.

## Author

**Mohammed Altounsi**

I build payment systems, e-commerce stores, and the web apps and marketing that
run around them. This repo is one working example: a payments and wallet ledger
designed to stay correct under retries, race conditions, and webhook redelivery,
and hardened to run in production.

- LinkedIn: <https://www.linkedin.com/in/mohammed-altounsi/>
- GitHub: [@MohammedAltounsi](https://github.com/MohammedAltounsi)
- Email: mhmdaltounsi@gmail.com

## License

MIT. See [LICENSE](LICENSE).
