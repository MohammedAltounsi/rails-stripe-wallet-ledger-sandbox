Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Stripe posts payment events here (server-to-server).
  post "webhooks/stripe", to: "webhooks/stripe#create"

  # Storefront
  root "products#index"
  get "products/:id", to: "products#show", as: :product

  resource :cart, only: [:show]
  post   "cart/items", to: "carts#add",    as: :cart_items   # add a customized line
  patch  "cart/line",  to: "carts#update", as: :cart_line    # change quantity (by line key)
  delete "cart/line",  to: "carts#remove"                    # remove a line (by line key)

  # Demo: switch which customer you're shopping as
  post "switch/:ref", to: "sessions#switch", as: :switch_customer

  # Wallet ("Dallah Card") top-up via Stripe Payment Element
  get  "wallet",       to: "wallet#show",  as: :wallet
  post "wallet/topup", to: "wallet#topup", as: :wallet_topup

  # Checkout — pickup + payment
  get  "checkout", to: "checkout#show",   as: :checkout
  post "checkout", to: "checkout#create"

  resources :orders, only: [:index, :show]

  get "ledger",         to: "accounts#index",        as: :ledger
  get "reconciliation", to: "reconciliation#show",   as: :reconciliation
end
