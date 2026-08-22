class ReconciliationController < ApplicationController
  # The report walks every Stripe PaymentIntent, so an uncached public endpoint
  # is a free amplification/DoS vector against the Stripe API rate limit. Cache
  # the result: at most one Stripe scan every 5 minutes no matter the traffic.
  # rack-attack throttles the endpoint on top of this.
  def show
    @result = Rails.cache.fetch("reconciliation:v1", expires_in: 5.minutes) { ReconciliationService.run }
  end
end
