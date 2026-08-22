# Run nightly (or on demand). Logs the result and re-raises nothing — it only
# reports. Schedule via config/recurring.yml with Solid Queue, e.g.:
#
#   production:
#     nightly_reconciliation:
#       class: ReconciliationJob
#       schedule: "every day at 3am"
class ReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    r = ReconciliationService.run
    if r.ok?
      Rails.logger.info("[reconcile] OK — #{r.matched} Stripe payments match the ledger, books sum to zero.")
    else
      Rails.logger.error(
        "[reconcile] DRIFT — missing=#{r.missing.size} mismatched=#{r.mismatched.size} " \
        "orphans=#{r.orphans.size} unbalanced=#{r.unbalanced_entries.size} global_sum=#{r.global_sum_cents}"
      )
    end
    r
  end
end
