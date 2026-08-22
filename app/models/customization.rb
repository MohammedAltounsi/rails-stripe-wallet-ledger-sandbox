# The drink-customization rules, in one place. Prices are always recomputed on
# the server from these constants — the client never sends a price we trust.
module Customization
  # size => price delta in halalas (Tall is the base price)
  SIZES = { "Tall" => 0, "Grande" => 300, "Venti" => 600 }.freeze

  MILKS  = ["Whole", "Skim", "Oat", "Almond", "Soy", "Coconut"].freeze  # all free
  SYRUPS = ["None", "Vanilla", "Caramel", "Hazelnut", "Saffron"].freeze # all free
  SHOTS  = [0, 1, 2].freeze                                             # extra shots
  SHOT_PRICE = 400                                                      # per extra shot
  TEMPS  = ["Hot", "Iced"].freeze

  DEFAULTS = { "size" => "Tall", "milk" => "Whole", "syrup" => "None", "shots" => 0 }.freeze

  module_function

  # Final unit price for a product with the chosen options.
  def price_cents(product, opts)
    base  = product.price_cents
    base += SIZES.fetch(opts["size"], 0)
    base += opts["shots"].to_i.clamp(0, 2) * SHOT_PRICE
    base
  end

  # Human-readable one-line summary: "Grande · Iced · Oat · +1 shot · Vanilla"
  def summary(opts)
    parts = []
    parts << opts["size"] if opts["size"]
    parts << opts["temperature"] if opts["temperature"].present?
    parts << "#{opts['milk']} milk" if opts["milk"].present? && opts["milk"] != "Whole"
    parts << "+#{opts['shots']} shot#{'s' if opts['shots'].to_i > 1}" if opts["shots"].to_i > 0
    parts << opts["syrup"] if opts["syrup"].present? && opts["syrup"] != "None"
    parts.join(" · ")
  end

  # Normalize whatever the form sent into a clean options hash.
  def clean(params, product)
    {
      "size"        => SIZES.key?(params[:size]) ? params[:size] : "Tall",
      "temperature" => temperature_for(params[:temperature], product),
      "milk"        => MILKS.include?(params[:milk]) ? params[:milk] : "Whole",
      "syrup"       => SYRUPS.include?(params[:syrup]) ? params[:syrup] : "None",
      "shots"       => params[:shots].to_i.clamp(0, 2)
    }
  end

  def temperature_for(requested, product)
    case product.temperature
    when "hot"  then "Hot"
    when "iced" then "Iced"
    else TEMPS.include?(requested) ? requested : "Hot"
    end
  end
end
