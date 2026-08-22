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
    # Integer/BigDecimal only — no float in the money path.
    amount = params[:amount_cents].presence&.to_i ||
             (params[:amount_sar].present? ? (BigDecimal(params[:amount_sar].to_s) * 100).to_i : 0)
    if amount < MIN || amount > MAX
      redirect_to wallet_path, alert: "Choose an amount between #{helpers.money(MIN)} and #{helpers.money(MAX)}." and return
    end

    # Idempotency key on a 30s bucket: a double-submit of the same top-up dedupes
    # to one PaymentIntent, but a deliberate repeat top-up later gets a fresh one.
    intent = StripeGateway.create_topup_intent(
      customer_ref: current_customer.ref,
      amount_cents: amount,
      key: "topup:#{current_customer.ref}:#{amount}:#{Time.now.to_i / 30}"
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
