class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  def subtotal_cents
    quantity * unit_price_cents
  end

  # "Grande · Iced · Oat milk · +1 shot · Vanilla"
  def options_summary
    Customization.summary(
      "size" => size, "temperature" => temperature,
      "milk" => milk, "syrup" => syrup, "shots" => shots
    )
  end
end
