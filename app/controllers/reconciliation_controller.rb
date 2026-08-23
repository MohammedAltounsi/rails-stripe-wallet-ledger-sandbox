class ReconciliationController < ApplicationController
  # The report walks every Stripe PaymentIntent, so an uncached public endpoint
  # is a free amplification/DoS vector against the Stripe API rate limit. Cache
  # the result: at most one Stripe scan every 5 minutes no matter the traffic.
  # rack-attack throttles the endpoint on top of this.
  def show
    @result = Rails.cache.fetch("reconciliation:v1", expires_in: 5.minutes) { ReconciliationService.run }
    # Webhook inbox health: a cheap DB read, so no need to cache it.
    @events        = StripeEvent.group(:status).count      # { "processed" => n, "failed" => n, ... }
    @failed_events = StripeEvent.failed.order(created_at: :desc).limit(10)
  end
end
