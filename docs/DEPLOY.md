# Deploying Dallah Coffee

Rails 8 + **PostgreSQL** (the ledger) on **Render** (web) + **Neon** (database).
Everything in the codebase is ready; the steps below are the ones only you can do
(they need your accounts).

Total time: about 20 to 30 minutes.

---

## What's already wired (no action needed)

- `render.yaml`: Render Blueprint (Docker web service, Frankfurt, health check `/up`).
- `config/database.yml`: production `primary` points at Postgres via `DATABASE_URL`.
- `Dockerfile`: Postgres client libs added; builds `pg` on Linux.
- `lib/tasks/db_constraints.rake`: installs the **deferred double-entry trigger** on Postgres.
- `bin/docker-entrypoint`: on boot it migrates, installs the trigger, seeds the menu once, and funds the demo cards.
- `pg` is locked for Linux only, so your Windows dev bundle is untouched (still SQLite).

---

## Step 1: Push to GitHub

Create an empty repo on GitHub, then, in **PowerShell**:

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
git remote add origin https://github.com/<your-username>/<your-repo>.git
```
```bash
git push -u origin main
```

## Step 2: Create the database (Neon)

1. Sign up at **neon.tech** (free, no card).
2. New Project, name it `dallah`. Region: **Frankfurt** (closest to Saudi).
3. On the project dashboard, copy the **connection string** (it looks like
   `postgresql://user:pass@ep-xxx.eu-central-1.aws.neon.tech/neondb?sslmode=require`).
   Use the **pooled** connection string if offered. Keep it for Step 4.

## Step 3: Get your master key

Your production app needs the Rails master key. Print it (do **not** commit it):

```bash
Get-Content config/master.key
```

Copy that value for Step 4.

## Step 4: Create the Render service (Blueprint)

1. Sign up at **render.com**.
2. **New, then Blueprint**, and connect your GitHub repo. Render reads `render.yaml`.
3. It will ask for the 5 secret env vars (marked `sync:false`). Set:
   | Key | Value |
   |---|---|
   | `RAILS_MASTER_KEY` | the value from Step 3 |
   | `DATABASE_URL` | the Neon string from Step 2 |
   | `STRIPE_PUBLISHABLE_KEY` | your `pk_test_…` (from `.env.local`) |
   | `STRIPE_SECRET_KEY` | your `sk_test_…` (from `.env.local`) |
   | `STRIPE_WEBHOOK_SECRET` | leave blank for now, set in Step 6 |
4. Click **Apply**. First build takes about 5 to 8 min. When it's live you get a URL like
   `https://dallah-coffee.onrender.com`.

On first boot the container migrates, installs the double-entry trigger, seeds the
menu, and funds the demo cards automatically, so the store is populated with no
shell access needed.

## Step 5: Confirm it's up

Open the URL. You should see the menu with photos, funded demo cards in the
switcher, and `/ledger` + `/reconciliation` working.

## Step 6: Point Stripe at the live webhook

The local `stripe listen` secret does **not** work in production. Create a real
endpoint:

1. Stripe Dashboard (**test mode**), then **Developers, Webhooks, Add endpoint**.
2. Endpoint URL: `https://<your-app>.onrender.com/webhooks/stripe`
3. Events: select **`payment_intent.succeeded`**.
4. Add endpoint, then copy its **Signing secret** (`whsec_…`).
5. Render, then your service, then **Environment**, and set `STRIPE_WEBHOOK_SECRET` to that
   value, then **Save** (Render redeploys automatically).

## Step 7: Test a real payment

1. On the live site: add a drink, checkout, **Pay by card**, or top up the
   Dallah Card.
2. Use the on-screen test card: **4242 4242 4242 4242**, exp `12/34`, CVC `123`.
3. After it clears, the wallet balance and order flip to paid. That is the live
   webhook crediting through the ledger.
4. Check `/reconciliation`.

## Step 8: Email receipts (SMTP)

A paid order emails a receipt to the address entered at checkout. Locally this
opens in your browser (letter_opener). In production it goes through SMTP. Set
these env vars on Render:

| Key | Value |
|---|---|
| `APP_HOST` | your live host, e.g. `dallah-coffee.onrender.com` (no `https://`) |
| `MAILER_FROM` | `Dallah Coffee <receipts@yourdomain.com>` |
| `SMTP_ADDRESS` | your provider's SMTP host |
| `SMTP_PORT` | `587` (already set) |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | from your provider |

Recommended provider: **Resend** (resend.com, free 3,000/mo). Verify a domain so
receipts come from your own address, which lands in inboxes. Its SMTP is
`smtp.resend.com`, username `resend`, password is your API key. If you don't want
to verify a domain, **Brevo** (free 300/day) sends from any address after signup.
Leave `SMTP_ADDRESS` unset and the app just skips sending (no crash).

`SOLID_QUEUE_IN_PUMA=true` (already in `render.yaml`) runs the job worker inside
the web process, so `deliver_later` actually sends on a single-service plan.

---

## Notes & troubleshooting

- **Free tier sleeps.** On Render's free plan the service spins down after about
  15 min idle and cold-starts in 30 to 60 s on the next visit. Upgrade the service
  to keep it always on for a live showcase.
- **"No open ports detected".** `HTTP_PORT` is set to `10000` in `render.yaml` to
  match Render's default. If Render logs expect a different port, set `HTTP_PORT`
  to that value.
- **The double-entry trigger** is installed on every boot (idempotent) and only on
  Postgres (see `lib/tasks/db_constraints.rake`). To see it reject bad data, open
  a Neon SQL console and try inserting a single unbalanced posting: the commit
  fails with `ledger integrity: entry … postings sum to …`.
- **Secrets** live only in Render and Neon dashboards and your local `.env.local`
  (gitignored). Nothing sensitive is in the repo.
