# Security Policy

## Scope

This is a portfolio project demonstrating payments engineering practices. It
runs entirely against **Stripe test mode**. No real card, no real money, and
no real customer data ever touches it (the seeded customers and orders are
fictional, and the demo has no login by design; see the README's "Demo
notes"). Treat findings here as you would for any production payments
codebase; the fix matters even though the stakes on this specific deployment
don't.

## Supported versions

There are no version branches. This app is continuously deployed from `main`
to a single live instance. A fix lands as a commit to `main`, not a backport.

## What's already enforced

- Every Stripe webhook is signature-verified (`Stripe::Webhook.construct_event`)
  before any code runs against its payload. A forged or malformed request is
  rejected with no side effects.
- Money is booked only from the verified webhook, never from creating a
  PaymentIntent. See `app/controllers/webhooks/stripe_controller.rb`.
- A wallet spend locks the wallet row (`SELECT ... FOR UPDATE`) inside the
  same transaction as the debit, so two concurrent checkouts can't both read
  the same balance and overdraw it.
- Content Security Policy with per-request script nonces, `force_ssl` with
  HSTS, and a host allowlist (`config/environments/production.rb`).
- rack-attack throttles the mutating endpoints (wallet, checkout, cart).
- All secrets (Stripe keys, database URL, Rails master key, SMTP credentials)
  come from environment variables. `config/master.key` and `.env.local` are
  gitignored; nothing sensitive is committed.
- Brakeman (static analysis) and bundler-audit (known gem CVEs) run on every
  push and every pull request, and a finding fails CI.
- Idempotency is enforced at the database level (unique indexes on
  `orders.checkout_token` and `entries.idempotency_key`), not just checked in
  application code, so a race condition can't double-charge or double-spend.
- A deferred Postgres trigger rejects any wallet balance that would go
  negative at commit, independent of the app-level lock above.

## Reporting a vulnerability

Open a [private security advisory](https://github.com/MohammedAltounsi/rails-stripe-wallet-ledger-sandbox/security/advisories/new)
on this repo, or email **mhmdaltounsi@gmail.com** with a description and
reproduction steps. Since this runs in test mode with no real funds or
personal data at risk, there's no bug bounty, but every report gets read and
a real fix.

Please don't open a public issue for a security finding until it's resolved.
