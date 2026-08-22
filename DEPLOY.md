# Deploying Dallah Coffee

Rails 8 + **PostgreSQL** (the ledger) on **Render** (web) + **Neon** (database).
Both free tiers, no card required, and Neon does not expire — so the demo stays
up. Everything in the codebase is ready; the steps below are the ones only you
can do (they need your accounts).

Total time: ~20–30 minutes.

---

## What's already wired (no action needed)

- `render.yaml` — Render Blueprint (Docker web service, Frankfurt, health check `/up`).
- `config/database.yml` — production `primary` → Postgres via `DATABASE_URL`.
- `Dockerfile` — Postgres client libs added; builds `pg` on Linux.
- `lib/tasks/db_constraints.rake` — installs the **deferred double-entry trigger** on Postgres.
- `bin/docker-entrypoint` — on boot: migrate → install trigger → seed menu (once) → fund demo cards.
- `pg` is locked for Linux only, so your Windows dev bundle is untouched (still SQLite).

---

## Step 1 — Push to GitHub

Create an empty repo on GitHub (e.g. `dallah-coffee`), then, in **PowerShell**:

```bash
git add -A
```
```bash
git commit -m "Deploy: Postgres, double-entry DB constraint, Render blueprint"
```
```bash
git branch -M main
```
```bash
git remote add origin https://github.com/<your-username>/dallah-coffee.git
```
```bash
git push -u origin main
```

## Step 2 — Create the database (Neon)

1. Sign up at **neon.tech** (free, no card).
2. New Project → name it `dallah`. Region: **Frankfurt** (closest to Saudi).
3. On the project dashboard, copy the **connection string** (it looks like
   `postgresql://user:pass@ep-xxx.eu-central-1.aws.neon.tech/neondb?sslmode=require`).
   Use the **pooled** connection string if offered. Keep it for Step 4.

## Step 3 — Get your master key

Your production app needs the Rails master key. Print it (do **not** commit it):

```bash
Get-Content config/master.key
```

Copy that value for Step 4.

## Step 4 — Create the Render service (Blueprint)

1. Sign up at **render.com** (free, no card).
2. **New → Blueprint** → connect your GitHub repo. Render reads `render.yaml`.
3. It will ask for the 5 secret env vars (marked `sync:false`). Set:
   | Key | Value |
   |---|---|
   | `RAILS_MASTER_KEY` | the value from Step 3 |
   | `DATABASE_URL` | the Neon string from Step 2 |
   | `STRIPE_PUBLISHABLE_KEY` | your `pk_test_…` (from `.env.local`) |
   | `STRIPE_SECRET_KEY` | your `sk_test_…` (from `.env.local`) |
   | `STRIPE_WEBHOOK_SECRET` | leave blank for now — set in Step 6 |
4. Click **Apply**. First build takes ~5–8 min. When it's live you get a URL like
   `https://dallah-coffee.onrender.com`.

On first boot the container migrates, installs the double-entry trigger, seeds the
menu, and funds the demo cards automatically — so the store is populated with no
shell access needed.

## Step 5 — Confirm it's up

Open the URL. You should see the menu with photos, funded demo cards in the
switcher, and `/ledger` + `/reconciliation` working.

## Step 6 — Point Stripe at the live webhook

The local `stripe listen` secret does **not** work in production. Create a real
endpoint:

1. Stripe Dashboard (**test mode**) → **Developers → Webhooks → Add endpoint**.
2. Endpoint URL: `https://<your-app>.onrender.com/webhooks/stripe`
3. Events: select **`payment_intent.succeeded`**.
4. Add endpoint, then copy its **Signing secret** (`whsec_…`).
5. Render → your service → **Environment** → set `STRIPE_WEBHOOK_SECRET` to that
   value → **Save** (Render redeploys automatically).

## Step 7 — Test a real payment

1. On the live site: add a drink → checkout → **Pay by card**, or top up the
   Dallah Card.
2. Use the on-screen test card: **4242 4242 4242 4242**, exp `12/34`, CVC `123`.
3. After it clears, the wallet balance / order flips to paid — that's the live
   webhook crediting through the ledger.
4. Check `/reconciliation` shows **Clean**.

---

## Notes & troubleshooting

- **Free tier sleeps.** After ~15 min idle the service spins down; the next visit
  cold-starts in ~30–60 s. Fine for a showcase.
- **"No open ports detected".** `HTTP_PORT` is set to `10000` in `render.yaml` to
  match Render's default. If Render logs expect a different port, set `HTTP_PORT`
  to that value.
- **The double-entry trigger** is installed on every boot (idempotent) and only on
  Postgres — see `lib/tasks/db_constraints.rake`. To see it reject bad data, open
  a Neon SQL console and try inserting a single unbalanced posting: the commit
  fails with `ledger integrity: entry … postings sum to …`.
- **Secrets** live only in Render/Neon dashboards and your local `.env.local`
  (gitignored). Nothing sensitive is in the repo.
