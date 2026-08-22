class OrdersController < ApplicationController
  # Orders are scoped to THIS browser session, not the shared demo customer.
  # Several visitors can shop as the same seeded customer (layla/omar/sara), so
  # keying visibility to the session is what stops one visitor from reading
  # another's receipt (and the real email they entered at checkout).
  def index
    @orders = Order.where(id: session_order_ids).includes(:order_items).order(created_at: :desc)
  end

  def show
    @order = Order.where(id: session_order_ids).includes(order_items: :product).find(params[:id])
  end

  private

  def session_order_ids
    Array(session[:order_ids])
  end
end
