class OrderMailer < ApplicationMailer
  # Sent once an order is paid (from the wallet flow and from the Stripe webhook).
  def receipt(order)
    @order = order
    @items = order.order_items.includes(:product)
    mail(to: order.email, subject: "Your Dallah Coffee receipt · #{order.reference}")
  end
end
