class CheckoutController < ApplicationController
  STORES = ["Dallah — Tahlia St", "Dallah — Corniche", "Dallah — Al Rawdah"].freeze

  def show
    @line_items = cart_line_items
    redirect_to(root_path, alert: "Your cart is empty.") and return if @line_items.empty?
    @total_cents   = cart_total_cents
    @balance_cents = current_customer.wallet_balance_cents
    @stores        = STORES
  end

  def create
    @line_items = cart_line_items
    redirect_to(root_path, alert: "Your cart is empty.") and return if @line_items.empty?

    case params[:pay]
    when "wallet" then pay_with_wallet
    when "card"   then pay_with_card
    else redirect_to checkout_path
    end
  end

  private

  # Pay from the Dallah Card (wallet). Debit + book revenue + mark paid, atomically.
  def pay_with_wallet
    total = cart_total_cents
    if current_customer.wallet_balance_cents < total
      short = total - current_customer.wallet_balance_cents
      redirect_to(checkout_path, alert: "Not enough Dallah Card balance — top up #{helpers.money(short)} more.") and return
    end

    order = nil
    ActiveRecord::Base.transaction do
      order = build_order("wallet")
      order.status = "paid"
      order.save!
      Ledger.post!(
        "wallet order #{order.reference}",
        [[current_customer.wallet_account, -total],
         [Ledger.account(Ledger::REVENUE_ACCOUNT), total]],
        key: "wallet-order:#{order.id}"
      )
    end

    session[:cart] = {}
    redirect_to order_path(order), notice: "Paid #{helpers.money(total)} from your Dallah Card."
  end

  # Pay by card: pending order + PaymentIntent, then the card form. The webhook
  # marks it paid — never here.
  def pay_with_card
    order = build_order("card")
    order.status = "pending"
    order.save!

    intent = StripeGateway.create_order_intent(order: order, key: "order-intent:#{order.id}")
    order.update!(stripe_payment_intent_id: intent.id)

    session[:cart] = {}
    @order           = order
    @client_secret   = intent.client_secret
    @publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"]
    render "checkout/card"
  end

  def build_order(method)
    store = STORES.include?(params[:pickup_store]) ? params[:pickup_store] : STORES.first
    order = current_customer.orders.build(
      payment_method: method,
      total_cents:    cart_total_cents,
      pickup_store:   store,
      pickup_time:    params[:pickup_time].presence || "As soon as possible"
    )
    cart_line_items.each do |li|
      order.order_items.build(
        product:         li[:product],
        quantity:        li[:qty],
        unit_price_cents: li[:unit_cents],
        size:            li[:opts]["size"],
        temperature:     li[:opts]["temperature"],
        milk:            li[:opts]["milk"],
        shots:           li[:opts]["shots"],
        syrup:           li[:opts]["syrup"]
      )
    end
    order
  end
end
