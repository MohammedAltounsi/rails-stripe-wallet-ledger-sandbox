class CartsController < ApplicationController
  def show
    @line_items  = cart_line_items
    @total_cents = cart_total_cents
  end

  # Add a customized drink. Identical customizations stack onto the same line.
  def add
    product = Product.available.find(params[:product_id])
    opts    = Customization.clean(params, product)
    qty     = params[:quantity].to_i.clamp(1, 20)
    qty     = 1 if qty.zero?
    key     = [product.id, opts["size"], opts["temperature"], opts["milk"], opts["syrup"], opts["shots"]].join("|")

    if cart[key]
      cart[key]["qty"] = cart[key]["qty"].to_i + qty
    else
      cart[key] = { "product_id" => product.id, "qty" => qty }.merge(opts)
    end
    redirect_to cart_path, notice: "Added to your order."
  end

  def update
    key = params[:key].to_s
    qty = params[:quantity].to_i
    if cart[key]
      qty <= 0 ? cart.delete(key) : cart[key]["qty"] = qty.clamp(1, 20)
    end
    redirect_to cart_path
  end

  def remove
    cart.delete(params[:key].to_s)
    redirect_to cart_path
  end
end
