# Changelog

This app is continuously deployed from `main`, not released in versioned
cuts, so entries are grouped by date instead of a version number. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) otherwise.

## 2026-08-24

### Added

- Webhook inbox (`StripeEvent`) for exactly-once processing of Stripe events,
  deduped on a unique `event_id`.

## 2026-08-23

### Added

- `ARCHITECTURE.md` and a reconciliation service test suite.

### Fixed

- Solid Queue's in-Puma supervisor pushed a 512 MB Starter instance over its
  memory limit (OOM, exit 137). Dropped it in favor of Active Job's `:async`
  adapter for receipt emails; kept a 5-connection database pool floor since
  Solid Cache still needs it.
- The Solid Queue disable didn't actually take: the Puma plugin needed to be
  gated on the env var's *value*, not just its presence, and a Render
  blueprint sync updates an env var's value but never deletes a stale key.

### Removed

- An unused Solid Queue recurring task, left over from before the `:async`
  switch.

## 2026-08-22

### Added

- Initial release: a double-entry ledger and Dallah Card wallet on Rails 8,
  with Stripe PaymentIntents for card top-ups and card checkout.
- Demo screenshots in the README.

### Fixed

- Binstub shebangs generated as `#!/usr/bin/env ruby.exe` by `rails new` on
  Windows, which isn't a valid interpreter path on the Linux CI runner or
  the Docker image. Committed with `#!/usr/bin/env ruby` and marked
  executable (`git update-index --chmod=+x`) so both actually run.

### Changed

- Render web service moved to the Starter plan for an always-on live demo
  (no cold start on a recruiter's first click).
