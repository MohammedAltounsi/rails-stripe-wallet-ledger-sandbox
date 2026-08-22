# Server-side Stripe calls authenticate with the secret key (test key = fake money).
Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
