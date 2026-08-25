# A stored reconciliation result, so drift has a timeline instead of scrolling
# out of the logs. Written by ReconciliationJob on every run.
class ReconciliationRun < ApplicationRecord
  scope :recent, -> { order(created_at: :desc) }

  def self.record(result)
    create!(
      status:           result.unreachable? ? "unreachable" : (result.ok? ? "clean" : "drift"),
      stripe_count:     result.stripe_count,
      matched:          result.matched,
      missing_count:    result.missing.size,
      mismatched_count: result.mismatched.size,
      orphan_count:     result.orphans.size,
      global_sum_cents: result.global_sum_cents
    )
  end

  def clean?       = status == "clean"
  def unreachable? = status == "unreachable"
end
