class WalletController < ApplicationController
  PRESETS = [2500, 5000, 10000].freeze   # SAR 25 / 50 / 100
  MIN = 500        # SAR 5
  MAX = 50_000     # SAR 500

  def show
    @balance_cents = current_customer.wallet_balance_cents
    @presets  = PRESETS
    @postings = wallet_history
  end

  # Create the PaymentIntent for a chosen amount, then render the card form.
  # Crediting happens later, in the webhook — never here.
  def topup
    amount = params[:amount_cents].presence&.to_i || (params[:amount_sar].to_f * 100).round
    if amount < MIN || amount > MAX
      redirect_to wallet_path, alert: "Choose an amount between #{helpers.money(MIN)} and #{helpers.money(MAX)}." and return
    end

    intent = StripeGateway.create_topup_intent(
      customer_ref: current_customer.ref,
      amount_cents: amount
    )
    @client_secret   = intent.client_secret
    @amount_cents    = amount
    @publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"]
    render :topup
  end

  private

  def wallet_history
    acct = Account.find_by(name: "wallet:#{current_customer.ref}")
    return [] unless acct
    Posting.where(account_id: acct.id).includes(:entry).order(created_at: :desc).limit(12)
  end
end
