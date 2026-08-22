module ApplicationHelper
  # Money is stored as integer minor units (halalas). This is the ONLY place it
  # becomes a display string — never do float math on money anywhere else.
  def money(cents)
    format("SAR %.2f", cents.to_i / 100.0)
  end

  # A stylized to-go cup, tinted to the drink's colour. Iced drinks get a clear
  # cup with cubes; hot drinks get steam. Self-contained SVG — no image assets.
  def cup_svg(color, iced: false, klass: "w-full h-full")
    liquid = color || "#c9a27a"
    steam  = iced ? "" : <<~STEAM
      <g stroke="#f4ede1" stroke-width="2.2" stroke-linecap="round" opacity="0.35" fill="none">
        <path d="M86 34 C82 28 90 24 86 18"/>
        <path d="M100 32 C96 26 104 22 100 16"/>
        <path d="M114 34 C110 28 118 24 114 18"/>
      </g>
    STEAM
    cubes = iced ? <<~CUBES : ""
      <g fill="#ffffff" opacity="0.22">
        <rect x="84" y="70" width="16" height="16" rx="3" transform="rotate(12 92 78)"/>
        <rect x="104" y="82" width="14" height="14" rx="3" transform="rotate(-8 111 89)"/>
        <rect x="92" y="96" width="15" height="15" rx="3" transform="rotate(6 99 103)"/>
      </g>
    CUBES

    raw <<~SVG
      <svg viewBox="0 0 200 200" class="#{klass}" role="img" aria-hidden="true">
        #{steam}
        <path d="M64 54 L136 54 L126 168 C125 176 119 180 112 180 L88 180 C81 180 75 176 74 168 Z"
              fill="#{liquid}" opacity="0.92"/>
        <path d="M64 54 L136 54 L134 76 L66 76 Z" fill="#ffffff" opacity="0.12"/>
        #{cubes}
        <rect x="58" y="46" width="84" height="14" rx="7" fill="#c8a35b"/>
        <path d="M64 54 L136 54 L126 168 C125 176 119 180 112 180 L88 180 C81 180 75 176 74 168 Z"
              fill="none" stroke="#1b1610" stroke-opacity="0.25" stroke-width="2"/>
      </svg>
    SVG
  end

  # Soft radial wash behind a drink, tinted to its colour.
  def drink_wash(color)
    "background: radial-gradient(120% 100% at 30% 15%, #{color}33, transparent 62%), linear-gradient(160deg, rgba(255,255,255,.03), rgba(0,0,0,.18));"
  end

  # A drink's product photo, sized by the caller's +klass+ (the container).
  # The real photo sits on top of the stylized cup_svg; if the photo ever
  # fails to load it removes itself and the SVG shows through. So there is
  # never a broken-image icon and no product ever renders empty.
  def product_media(product, klass:, iced: false)
    fallback = cup_svg(product.color, iced: iced, klass: "h-2/3 w-2/3")
    img =
      if product.image_url.present?
        tag.img(src: product.image_url, alt: product.name, loading: "lazy",
                class: "absolute inset-0 h-full w-full object-cover",
                onerror: "this.remove()")
      end
    content_tag(:div, class: "relative overflow-hidden grid place-items-center #{klass}",
                      style: drink_wash(product.color)) do
      safe_join([fallback, img].compact)
    end
  end
end
