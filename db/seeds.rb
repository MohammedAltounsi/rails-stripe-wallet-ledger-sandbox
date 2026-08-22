# Idempotent seeds — upserts, safe to run repeatedly.

# --- Demo customers -------------------------------------------------------
[
  { name: "Layla", ref: "layla", email: "layla@example.com" },
  { name: "Omar",  ref: "omar",  email: "omar@example.com" },
  { name: "Sara",  ref: "sara",  email: "sara@example.com" }
].each do |attrs|
  c = Customer.find_or_initialize_by(ref: attrs[:ref])
  c.update!(name: attrs[:name], email: attrs[:email])
end

# --- Dallah menu ----------------------------------------------------------
# price_cents is the base (Tall) price. temperature: hot / iced / both.
# Product photos: curated, licence-free Pexels images (verified 2026-08-22).
px = ->(id) { "https://images.pexels.com/photos/#{id}/pexels-photo-#{id}.jpeg?auto=compress&cs=tinysrgb&w=800" }
menu = [
  # Hot Coffee
  { name: "Caffè Latte",        category: "Hot Coffee", price_cents: 1800, temperature: "both", color: "#c9a27a", emoji: "☕", tagline: "Espresso · steamed milk", image_url: px.(12703064),
    description: "Two shots pulled long under smooth steamed milk and a thin layer of foam." },
  { name: "Flat White",         category: "Hot Coffee", price_cents: 2000, temperature: "both", color: "#c19a6b", emoji: "🤍", tagline: "Ristretto · microfoam", image_url: px.(30291137),
    description: "Two ristretto shots under a thin layer of silky microfoam. Stronger than a latte." },
  { name: "Cappuccino",         category: "Hot Coffee", price_cents: 1900, temperature: "hot",  color: "#b98d5e", emoji: "☕", tagline: "Equal parts, more foam", image_url: px.(2396220),
    description: "Espresso, steamed milk and a deep cap of airy foam. A classic morning cup." },
  { name: "Cortado",            category: "Hot Coffee", price_cents: 1900, temperature: "hot",  color: "#a9784b", emoji: "🤎", tagline: "Cut with warm milk", image_url: px.(14704662),
    description: "Espresso cut with an equal measure of warm milk. Small, balanced, strong." },
  { name: "Spanish Latte",      category: "Hot Coffee", price_cents: 2200, temperature: "both", color: "#c8a06f", emoji: "🥛", tagline: "Condensed milk", image_url: px.(302900),
    description: "Double espresso over sweetened condensed milk and steamed whole milk." },

  # Iced Coffee
  { name: "Iced Spanish Latte", category: "Iced Coffee", price_cents: 2400, temperature: "iced", color: "#caa678", emoji: "🧊", tagline: "Over ice", image_url: px.(10738363),
    description: "The Spanish latte, shaken and poured over ice for the Jeddah heat." },
  { name: "Cold Brew",          category: "Iced Coffee", price_cents: 2300, temperature: "iced", color: "#5a3b26", emoji: "🧋", tagline: "18-hour steep", image_url: px.(17576001),
    description: "Steeped cold for eighteen hours. Smooth, low-acid, quietly strong." },
  { name: "Iced Shaken Espresso", category: "Iced Coffee", price_cents: 2500, temperature: "iced", color: "#7a4f30", emoji: "🧊", tagline: "Shaken, then poured", image_url: px.(34170574),
    description: "Four ristretto shots shaken with ice and a touch of syrup, topped with milk." },

  # Signature
  { name: "Saudi Qahwa",        category: "Signature", price_cents: 1800, temperature: "hot",  color: "#caa14f", emoji: "🫖", tagline: "Cardamom · saffron", image_url: px.(30146018),
    description: "Lightly roasted Arabica brewed with cardamom and a thread of saffron. Served the traditional way." },
  { name: "Saffron Latte",      category: "Signature", price_cents: 2600, temperature: "both", color: "#d9b25a", emoji: "🌼", tagline: "Saffron · honey", image_url: px.(30357453),
    description: "Espresso and steamed milk infused with saffron and a spoon of honey." },

  # Tea & More
  { name: "Karak Chai",         category: "Tea & More", price_cents: 1500, temperature: "hot",  color: "#b5794a", emoji: "🫖", tagline: "Spiced · evaporated milk", image_url: px.(186857),
    description: "Strong black tea simmered with cardamom and evaporated milk. Jeddah street-style." },
  { name: "Matcha Latte",       category: "Tea & More", price_cents: 2400, temperature: "both", color: "#7fa86b", emoji: "🍵", tagline: "Ceremonial grade", image_url: px.(8634757),
    description: "Stone-ground ceremonial matcha whisked with milk. Grassy, sweet, vivid green." }
]

menu.each_with_index do |attrs, i|
  p = Product.find_or_initialize_by(name: attrs[:name])
  p.update!(attrs.merge(active: true, position: i + 1))
end

# Retire any older seed items no longer on the menu.
Product.where.not(name: menu.map { |m| m[:name] }).update_all(active: false)

puts "Seeded #{Customer.count} customers, #{Product.available.count} products across #{Product.available.map(&:category).uniq.size} categories."
