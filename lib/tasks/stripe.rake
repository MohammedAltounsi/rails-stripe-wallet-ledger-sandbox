namespace :stripe do
  desc "Reprocess Stripe inbox events stuck in received/failed (recovery sweep)"
  task reprocess: :environment do
    n = ReprocessStuckStripeEventsJob.perform_now
    puts "Reprocessed #{n} stuck event(s)."
  end
end
