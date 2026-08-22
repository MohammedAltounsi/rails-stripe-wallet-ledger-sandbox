class CheckoutController < ApplicationController
  STORES = ["Dallah, Tahlia St", "Dallah, Corniche", "Dallah, Al Rawdah"].freeze

  def show
    @line_items = cart_line_items
    redirect_to(root_path, alert: "Your cart is empty.") and return if @line_items.empty?
    # One idempotency token per checkout attempt. Reused by a double-tap so the
    # unique index on orders.checkout_token collapses the duplicate.
    session[:checkout_token] ||= SecureRandom.uuid
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
  rescue ActiveRecord::RecordNotUnique
    # Concurrent double-submit: an order already exists for this checkout token.
    # Send the shopper to it instead of charging or creating a second one.
    existing = Order.find_by(checkout_token: session[:checkout_token])
    redirect_to existing ? order_path(existing) : root_path
  end

  private

  # Pay from the Dallah Card (wallet). Debit + book revenue + mark paid, atomically.
  #
  # The balance check and the debit happen INSIDE one transaction, and the wallet
  # account row is locked (SELECT ... FOR UPDATE) first. Without the lock, two
  # concurrent checkouts (double-tap Pay, two tabs) each read the same balance,
  # each pass the check, and each debit — draining the wallet negative. The lock
  # serializes them: the second waits, re-reads the now-lower balance, and is
  # correctly rejected. The Postgres wallet_no_overdraft trigger is the backstop.
  def pay_with_wallet
    order = nil
    short = nil

    ActiveRecord::Base.transaction do
      wallet = current_customer.wallet_account
      wallet.lock!                       # FOR UPDATE — no one else moves this wallet until we commit
      total = cart_total_cents
      if wallet.balance_cents < total
        short = total - wallet.balance_cents
        raise ActiveRecord::Rollback     # abort cleanly; nothing was written
      end

      order = build_order("wallet")
      order.status = "paid"
      order.save!
      Ledger.post!(
        "wallet order #{order.reference}",
        [[wallet, -total],
         [Ledger.account(Ledger::REVENUE_ACCOUNT), total]],
        key: "wallet-order:#{order.id}"
      )
    end

    if short
      return redirect_to(checkout_path, alert: "Not enough Dallah Card balance. Top up #{helpers.money(short)} more.")
    end

    remember_order(order)
    session[:cart] = {}
    session.delete(:checkout_token)   # next checkout gets a fresh token
    sent = deliver_receipt(order)   # payment is already committed; a mail hiccup can't undo it
    note = "Paid #{helpers.money(order.total_cents)} from your Dallah Card."
    note += " Receipt sent to #{order.email}." if sent
    redirect_to order_path(order), notice: note
  end

  # Enqueue the receipt email, swallowing any failure so it never affects a
  # committed payment. Returns true if it was enqueued.
  def deliver_receipt(order)
    return false if order.email.blank?
    OrderMailer.receipt(order).deliver_later
    true
  rescue => e
    Rails.logger.error("receipt email failed for #{order&.reference}: #{e.message}")
    false
  end

  # Pay by card: pending order + PaymentIntent, then the card form. The webhook
  # marks it paid — never here.
  def pay_with_card
    order = build_order("card")
    order.status = "pending"
    order.save!

    # Key includes the random order reference so it can't collide with a reused
    # order id from another database on the same Stripe test account.
    intent = StripeGateway.create_order_intent(order: order, key: "order-intent:#{order.id}-#{order.reference}")
    order.update!(stripe_payment_intent_id: intent.id)

    remember_order(order)
    session[:cart] = {}
    session.delete(:checkout_token)   # next checkout gets a fresh token
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
      pickup_time:    params[:pickup_time].presence || "As soon as possible",
      email:          params[:email].presence || current_customer.email,
      checkout_token: session[:checkout_token]
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

  # This browser session's own orders. Order visibility is scoped to this so one
  # visitor can never read the receipt (and real email) of another visitor who
  # happens to be shopping as the same shared demo customer.
  def remember_order(order)
    session[:order_ids] = (Array(session[:order_ids]) + [order.id]).last(50)
  end
end
