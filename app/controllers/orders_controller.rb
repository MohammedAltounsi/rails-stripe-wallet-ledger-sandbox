class OrdersController < ApplicationController
  def index
    @orders = current_customer.orders.includes(:order_items).order(created_at: :desc)
  end

  def show
    # Scoped to the current customer — you can't read someone else's receipt.
    @order = current_customer.orders.includes(order_items: :product).find(params[:id])
  end
end
