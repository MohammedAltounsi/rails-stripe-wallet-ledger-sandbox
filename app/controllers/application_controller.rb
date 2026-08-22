class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  helper_method :current_customer, :customers_for_switcher, :cart, :cart_count,
                :cart_line_items, :cart_total_cents

  private

  def current_customer
    @current_customer ||=
      Customer.find_by(id: session[:customer_id]) || Customer.order(:id).first
  end

  def customers_for_switcher
    Customer.order(:id)
  end

  # Cart lives in the session. Each entry is one customized line:
  #   line_key => { "product_id", "qty", "size", "temperature", "milk", "syrup", "shots" }
  def cart
    c = session[:cart] ||= {}
    # Self-heal a cart left over from an older format: every line must be a Hash
    # ({ "product_id", "qty", ...}). If not, it's stale — reset it.
    c = session[:cart] = {} unless c.is_a?(Hash) && c.values.all? { |v| v.is_a?(Hash) }
    c
  end

  def cart_count
    cart.values.sum { |line| line["qty"].to_i }
  end

  # Resolve the session cart into rich line items, pricing each one on the server
  # from the current product price + its options — never trusting a client price.
  def cart_line_items
    by_id = Product.where(id: cart.values.map { |l| l["product_id"] }).index_by(&:id)
    cart.filter_map do |key, line|
      product = by_id[line["product_id"].to_i]
      next unless product && line["qty"].to_i > 0
      opts = line.slice("size", "temperature", "milk", "syrup", "shots")
      unit = Customization.price_cents(product, opts)
      {
        key: key, product: product, opts: opts, qty: line["qty"].to_i,
        unit_cents: unit, subtotal_cents: unit * line["qty"].to_i
      }
    end
  end

  def cart_total_cents
    cart_line_items.sum { |li| li[:subtotal_cents] }
  end
end
